#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

eval "$(awk '/^curl_with_retry[(][)] [{]/,/^}/' "$CORE_DIR/lib/system.func")"
eval "$(awk '/^setup_deb822_repo[(][)] [{]/,/^}/' "$CORE_DIR/lib/system.func" |
  sed -e "s#/etc/apt/keyrings#$TEST_DIR/keyrings#g" \
    -e "s#/etc/apt/sources.list.d#$TEST_DIR/sources#g")"

LOG="$TEST_DIR/calls"
# shellcheck disable=SC2034
STD=""
debug_log() { :; }
msg_error() { echo "error: $*" >>"$LOG"; }
cleanup_old_repo_files() { :; }
cleanup_orphaned_sources() { :; }
apt() { echo "apt $*" >>"$LOG"; }
getent() { echo "getent $*" >>"$LOG"; [[ "$2" == *.example.org ]]; }
curl() {
  echo "curl ${*: -1}" >>"$LOG"
  local out=""
  while (($#)); do
    [[ "$1" == "-o" ]] && out="$2"
    shift
  done
  [[ -n "$out" ]] && printf 'binary-key' >"$out"
  return 0
}

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
reset() {
  rm -rf "$TEST_DIR/keyrings" "$TEST_DIR/sources" "$LOG"
  mkdir -p "$TEST_DIR/sources"
  : >"$LOG"
}
signed_by() { sed -n 's/^Signed-By: //p' "$TEST_DIR/sources/$1.sources" 2>/dev/null; }

local_key="$TEST_DIR/debian-archive-keyring.gpg"
printf 'system-key' >"$local_key"

reset
rc=0
setup_deb822_repo debian-backports "$local_key" http://deb.debian.org/debian trixie-backports main || rc=$?
check "a local keyring succeeds" 0 "$rc"
check "a local keyring is used where it is" "$local_key" "$(signed_by debian-backports)"
check "a local keyring is neither downloaded nor looked up" "" "$(grep -E '^(curl|getent) ' "$LOG" || true)"
check "a local keyring is not copied" no "$([[ -e "$TEST_DIR/keyrings" ]] && echo yes || echo no)"
check "apt update still runs" "apt update" "$(grep '^apt ' "$LOG")"

reset
rc=0
setup_deb822_repo debian-backports "$TEST_DIR/missing.gpg" http://deb.debian.org/debian trixie-backports main || rc=$?
check "a missing local keyring fails as a missing resource" 252 "$rc"
check "a missing local keyring writes no sources file" no "$([[ -e "$TEST_DIR/sources/debian-backports.sources" ]] && echo yes || echo no)"

reset
setup_deb822_repo myapp https://repo.example.org/key.gpg https://repo.example.org/deb stable main
check "a key URL is downloaded into keyrings" "$TEST_DIR/keyrings/myapp.gpg" "$(signed_by myapp)"
check "the downloaded key is in place" binary-key "$(cat "$TEST_DIR/keyrings/myapp.gpg" 2>/dev/null)"

reset
rc=0
curl_with_retry file:///usr/share/keyrings/debian-archive-keyring.gpg "$TEST_DIR/out" >/dev/null || rc=$?
check "file:// skips the DNS pre-check" "0 curl file:///usr/share/keyrings/debian-archive-keyring.gpg" "$rc $(cat "$LOG")"

reset
rc=0
curl_with_retry https://unknown.invalid/key.gpg "$TEST_DIR/out" || rc=$?
check "an unresolvable https host still fails fast" "6 getent hosts unknown.invalid" "$rc $(cat "$LOG")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
