#!/usr/bin/env bash
# Issue Incus#559: from a client that drives a remote, the check for an imported
# image asked "local:", a daemon the client does not have, and every VM script
# continued on "Could not confirm a VM variant".
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^vm_check_image[(][)] [{]/,/^}/' "$CORE_DIR/incus/vm-core.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

msg_info() { :; }
msg_ok() { echo "ok" >>"$TEST_DIR/out"; }
msg_warn() { echo "warn" >>"$TEST_DIR/out"; }
fatal() { echo "fatal" >>"$TEST_DIR/out"; }
# Like incus 7.6: the list filter finds aliases on a simplestreams remote but not
# an imported alias; "local:" fails on a client without a daemon.
incus() {
  echo "$*" >>"$TEST_DIR/asked"
  local ref="$3"
  [[ "$ref" == *:* ]] || ref="${INCUS_REMOTE:-local}:$ref"
  [[ "$ref" == local:* && -n "${NO_LOCAL_DAEMON:-}" ]] && return 1
  case "$1 $2" in
  "image list") [[ "$ref" == images:* ]] && echo "debian/13 (7 more)" ;;
  "image info")
    [[ "$ref" == "${ON_SERVER:-}:"* || "$ref" == images:* ]] || return 1
    printf 'Fingerprint: de6e\nType: %s\n' "${TYPE:-virtual-machine}"
    ;;
  esac
  return 0
}
check() {
  : >"$TEST_DIR/out"
  : >"$TEST_DIR/asked"
  vm_check_image "$1"
}

INCUS_REMOTE=incus001 ON_SERVER=incus001 NO_LOCAL_DAEMON=1
check cs-haos_ova-18.4
expect "an imported image is looked up on the target remote" 0 "$(grep -c 'local:' "$TEST_DIR/asked")"
expect "and confirmed there" ok "$(cat "$TEST_DIR/out")"

INCUS_REMOTE=local ON_SERVER=local NO_LOCAL_DAEMON=""
check cs-haos_ova-18.4
expect "on the server itself the imported image is confirmed by its type" ok "$(cat "$TEST_DIR/out")"

TYPE=container
check cs-haos_ova-18.4
expect "an imported container image still warns" warn "$(cat "$TEST_DIR/out")"
TYPE=virtual-machine

INCUS_REMOTE=incus001 ON_SERVER=incus001
check images:debian/13
expect "an image server alias keeps its own remote" 1 "$(grep -c '^image list images:debian/13 type=virtual-machine' "$TEST_DIR/asked")"
expect "and is confirmed by the list" ok "$(cat "$TEST_DIR/out")"

ON_SERVER=other
check cs-missing
expect "an image that is nowhere still stops" fatal "$(cat "$TEST_DIR/out")"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
