#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^incus_target[(][)] [{]/,/^}/' "$CORE_DIR/incus/core.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/log"
passed=0 failed=0

incus_msg_custom() { echo "$3" >>"$LOG"; }
# The client answers for its default remote; `incus info` is the server's YAML.
incus() {
  case "$1 ${2:-}" in
  "remote get-default") echo "${MOCK_REMOTE:-local}" ;;
  "info ") printf 'config: {}\nenvironment:\n  addresses: []\n  architectures:\n  - %s\n  - i686\n  server_name: box\n' "${MOCK_ARCH:-x86_64}" ;;
  esac
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

: >"$LOG"
MOCK_REMOTE=incusos MOCK_ARCH=aarch64 incus_target
expect "the default remote is the target" incusos "$INCUS_REMOTE"
expect "the server architecture is read, in Debian naming" arm64 "$INCUS_SERVER_ARCH"
expect "a remote target is announced" "Target: Incus remote 'incusos' (arm64)" "$(cat "$LOG")"

: >"$LOG"
MOCK_REMOTE=local MOCK_ARCH=x86_64 incus_target
expect "local stays local" local "$INCUS_REMOTE"
expect "x86_64 becomes amd64" amd64 "$INCUS_SERVER_ARCH"
expect "local is not announced" "" "$(cat "$LOG")"

MOCK_REMOTE=lab MOCK_ARCH=riscv64 incus_target
expect "an unmapped architecture is passed through" riscv64 "$INCUS_SERVER_ARCH"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
