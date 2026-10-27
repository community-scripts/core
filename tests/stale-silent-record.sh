#!/usr/bin/env bash
# silent() leaves its record for the ERR trap. After `$STD cmd || true` the
# record and its .errinfo stayed until the next $STD call, so a later plain
# command's failure was reported as the handled one.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(error_handler|_eh_source_line|_eh_resolve_log)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/install.log"
ERRINFO="$LOG.errinfo"
passed=0 failed=0

_eh_explanation() { echo "explained"; }
_eh_report() {
  printf 'REPORT %s|%s|%s\n' "$1" "$2" "$3"
  exit 0
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
handled_failure() {
  echo "E: Unable to locate package intel-basekit" >"$LOG"
  printf '%s\n' 'EXIT_CODE=100' 'LINE=5' 'COMMAND=apt install -y intel-basekit' '--- OUTPUT ---' 'E: Unable to locate package intel-basekit' >"$ERRINFO"
  export _SILENT_FAILED_RC=100 _SILENT_FAILED_CMD='apt install -y intel-basekit' _SILENT_FAILED_LINE="$1" _SILENT_FAILED_LOG="$LOG"
}

# A later failure on another line is its own.
handled_failure 5
out="$(error_handler 1 'systemctl enable -q --now open-webui')"
expect "the later failure keeps its code and command" 1 "$(grep -c 'REPORT 1|systemctl enable -q --now open-webui|' <<<"$out")"
expect "the handled failure's capture is dropped" 0 "$(ls "$ERRINFO" 2>/dev/null | wc -l)"

# On its own line the record is what the trap reports.
line=$LINENO; handled_failure "$line"; out="$(error_handler 1 'silent apt install -y intel-basekit')"
expect "silent's record is used for its own line" 1 "$(grep -c 'REPORT 100|apt install -y intel-basekit|' <<<"$out")"
expect "its capture is kept" 1 "$(ls "$ERRINFO" 2>/dev/null | wc -l)"

# A helper that handled it and passed it up with "return": that command is still what broke.
handled_failure 5
out="$(error_handler 100 'return 100')"
expect "a passed-up failure reports silent's command and line" 1 "$(grep -c 'REPORT 100|apt install -y intel-basekit|5' <<<"$out")"
expect "and keeps its capture" 1 "$(ls "$ERRINFO" 2>/dev/null | wc -l)"

# Without a record, "return N" is replaced by the call on that source line.
printf '%s\n' 'setup_thing() {' '  fetch_release foo' '}' >"$TEST_DIR/lib.sh"
unset _SILENT_FAILED_RC
out="$(BASH_EXECUTION_STRING='' _eh_source_line "$TEST_DIR/lib.sh" 2)"
expect "the source line names the failing call" "fetch_release foo" "$out"
out="$(BASH_EXECUTION_STRING=$'line one\n  $STD setup_uv' _eh_source_line "" 2)"
expect "a bash -c script is read from BASH_EXECUTION_STRING" "setup_uv" "$out"
expect "an unreadable source gives nothing" "" "$(BASH_EXECUTION_STRING='' _eh_source_line /dev/stdin 1)"

echo "$passed passed, $failed failed"
((failed == 0))
