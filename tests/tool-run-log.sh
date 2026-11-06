#!/usr/bin/env bash
# A host tool has no BUILD_LOG. Its log name was taken per call, so each second
# of a run went to another /tmp/build-*.log and no file held the failing step.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

unset _HOST_LOGFILE INSTALL_LOG BUILD_LOG _CS_RUN_LOG
# shellcheck disable=SC1091
source "$CORE_DIR/core/core.func"
trap - EXIT HUP

first="$(get_active_logfile)"
sleep 1.1
expect "one log for the whole run" "$first" "$(get_active_logfile)"
expect "SILENT_LOGFILE is that log" "$first" "$SILENT_LOGFILE"
expect "a build log still wins" /tmp/demo-build.log "$(BUILD_LOG=/tmp/demo-build.log get_active_logfile)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
