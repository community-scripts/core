#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^check_for_gl_tag[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR"
passed=0 failed=0

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

msg_info() { :; }
msg_ok() { :; }
get_latest_gl_tag() {
  echo "$1 $2" >"$TEST_DIR/asked"
  [[ -n "${MOCK_FAIL:-}" ]] && return 1
  echo "v4.6.1"
}

run() {
  local rc=0
  CHECK_UPDATE_RELEASE=""
  check_for_gl_tag "MusicGrabber" "g33kphr33k/musicgrabber" "v*" || rc=$?
  echo "$rc ${CHECK_UPDATE_RELEASE}"
}

check "not installed: update offered" "0 v4.6.1" "$(run)"
check "the pattern reaches the tag lookup" "g33kphr33k/musicgrabber v*" "$(cat "$TEST_DIR/asked")"
echo "v4.6.0" >"$TEST_DIR/.musicgrabber"
check "older stamp: update offered" "0 v4.6.1" "$(run)"
echo "v4.6.1" >"$TEST_DIR/.musicgrabber"
check "current stamp: no update" "1 " "$(run)"
check "a failed lookup is not an update" "22 " "$(MOCK_FAIL=1 run)"

echo "${passed} passed, ${failed} failed"
((failed == 0))
