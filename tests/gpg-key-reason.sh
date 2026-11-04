#!/usr/bin/env bash
# download_gpg_key returned 7 for every failure and the callers only said the
# key failed, so 14 Frigate runs and others carried no reason at all.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^download_gpg_key[(][)] [{]/,/^}/' "$CORE_DIR/lib/system.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
WARN="$TEST_DIR/warn"
passed=0 failed=0

debug_log() { :; }
sleep() { :; }
msg_warn() { echo "$*" >>"$WARN"; }
curl() {
  local out="" i
  local -a a=("$@")
  for ((i = 0; i < ${#a[@]}; i++)); do [[ "${a[$i]}" == -o ]] && out="${a[$((i + 1))]}"; done
  if [[ -n "${MOCK_CURL_ERR:-}" ]]; then
    echo "$MOCK_CURL_ERR" >&2
    return 28
  fi
  printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\nx\n-----END PGP PUBLIC KEY BLOCK-----\n' >"$out"
}
gpg() {
  [[ -n "${MOCK_GPG_ERR:-}" ]] && { echo "$MOCK_GPG_ERR" >&2; return 2; }
  local out=""
  while (($#)); do [[ "$1" == -o ]] && out="$2"; shift; done
  echo key >"$out"
}

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

: >"$WARN"
download_gpg_key https://example.com/k.key "$TEST_DIR/ok.gpg" dearmor
expect "a key that downloads and dearmors installs" 0 "$?"
expect "and says nothing" 0 "$(wc -l <"$WARN")"

: >"$WARN"
MOCK_CURL_ERR="curl: (28) Connection timed out after 10002 milliseconds" download_gpg_key https://example.com/k.key "$TEST_DIR/a.gpg" dearmor
expect "a failed download still returns 7" 7 "$?"
expect "and names curl's error" 1 "$(grep -c "https://example.com/k.key not installed after 3 attempts: curl: (28) Connection timed out" "$WARN")"

: >"$WARN"
MOCK_GPG_ERR="gpg: command not found" download_gpg_key https://example.com/k.key "$TEST_DIR/b.gpg" dearmor
expect "a failed dearmor returns 7" 7 "$?"
expect "and names gpg's error" 1 "$(grep -c "not installed after 3 attempts: gpg --dearmor: gpg: command not found" "$WARN")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
