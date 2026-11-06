#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(silent|_cs_shield_hangup|_cs_reattach_output)[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"

TEST_DIR="$(mktemp -d)"
LOG="$TEST_DIR/install.log"
passed=0 failed=0
VERBOSE=yes

get_active_logfile() { echo "$LOG"; }

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
out="$(silent sh -c 'echo first; echo second' 2>&1)"
expect "verbose output reaches the terminal" "first second" "$(echo $out)"
expect "and the log" 2 "$(grep -cE 'first|second' "$LOG")"

silent sh -c 'exit 3' >/dev/null 2>&1
expect "the exit code is kept" 3 "$?"

: >"$LOG"
start=$SECONDS
silent sh -c 'sleep 20 & echo daemon started' >/dev/null 2>&1
rc=$?
expect "a daemon that keeps the output pipe open does not hold the caller" 1 "$(((SECONDS - start) < 10 ? 1 : 0))"
expect "and the start still succeeds" 0 "$rc"
expect "its output is logged" 1 "$(grep -c 'daemon started' "$LOG")"

pkill -f 'sleep 20' 2>/dev/null
rm -rf -- "$TEST_DIR"
printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
