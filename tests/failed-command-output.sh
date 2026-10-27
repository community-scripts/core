#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(silent|set_std_mode|_cs_shield_hangup|_cs_reattach_output)[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^_eh_print_failed_output[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOGFILE="$TEST_DIR/install.log"
export TAB="  "
passed=0 failed=0

get_active_logfile() { echo "$LOGFILE"; }
debug_log() { :; }
# A failing command that talks on both streams, and a function with a side effect.
noisy() {
  echo "stdout line"
  echo "stderr line" >&2
  return 3
}
marker() {
  MARK="set"
  echo "marker ran"
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
reset() {
  : >"$LOGFILE"
  rm -f "$LOGFILE.errinfo"
  unset _SILENT_FAILED_RC _SILENT_FAILED_CMD _SILENT_FAILED_LINE _SILENT_FAILED_LOG MARK
}

# --- silent, quiet mode ---
reset
export VERBOSE=no
set_std_mode
expect "quiet mode runs through silent" silent "$STD"
$STD noisy >"$TEST_DIR/shown" 2>&1
rc=$?
expect "quiet: exit code is kept" 3 "$rc"
expect "quiet: nothing reaches the terminal" "" "$(cat "$TEST_DIR/shown")"
expect "quiet: silent reports the failure" 3 "${_SILENT_FAILED_RC:-unset}"
expect "quiet: both streams are in the log" 2 "$(grep -c 'line' "$LOGFILE")"
expect "quiet: errinfo records the exit code" 1 "$(grep -c '^EXIT_CODE=3$' "$LOGFILE.errinfo")"
expect "quiet: errinfo carries the output" 1 "$(grep -c '^stderr line$' "$LOGFILE.errinfo")"

# --- silent, verbose mode ---
reset
export VERBOSE=yes
set_std_mode
expect "verbose mode also runs through silent" silent "$STD"
$STD noisy >"$TEST_DIR/shown" 2>&1
rc=$?
expect "verbose: exit code is kept" 3 "$rc"
expect "verbose: the output is shown live" 2 "$(grep -c 'line' "$TEST_DIR/shown")"
expect "verbose: the output is still logged" 2 "$(grep -c 'line' "$LOGFILE")"
expect "verbose: errinfo is written" 1 "$(grep -c '^stderr line$' "$LOGFILE.errinfo")"
expect "verbose: silent reports the failure" 3 "${_SILENT_FAILED_RC:-unset}"

reset
$STD marker >/dev/null
expect "verbose: a function keeps its side effects" set "${MARK:-unset}"
expect "verbose: success leaves no errinfo" no "$([[ -f "$LOGFILE.errinfo" ]] && echo yes || echo no)"

# --- the host-side display of the failing command's output ---
ERRINFO="$TEST_DIR/errinfo"
long="$(printf 'x%.0s' $(seq 1 600))"
printf 'EXIT_CODE=1\nLINE=34\nCOMMAND=pnpm install --frozen-lockfile\n--- OUTPUT ---\nScope: all 36 workspace projects\n ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with "frozen-lockfile"\n%s\n' "$long" >"$ERRINFO"
shown="$(_eh_print_failed_output "$ERRINFO" 2>&1)"
expect "the failing output gets a heading" 1 "$(printf '%s\n' "$shown" | grep -c 'Output of the failing command')"
expect "the pnpm error is shown" 1 "$(printf '%s\n' "$shown" | grep -c 'ERR_PNPM_OUTDATED_LOCKFILE')"
expect "the header lines of errinfo are not shown" 0 "$(printf '%s\n' "$shown" | grep -c '^EXIT_CODE=')"
expect "overlong lines are cut" 400 "$(printf '%s\n' "$shown" | grep 'xxxx' | head -n1 | awk '{print length($0)}')"

printf 'EXIT_CODE=1\nLINE=34\nCOMMAND=true\n--- OUTPUT ---\n' >"$ERRINFO"
expect "an empty output section prints nothing" "" "$(_eh_print_failed_output "$ERRINFO" 2>&1)"
expect "a missing errinfo prints nothing" "" "$(_eh_print_failed_output "$TEST_DIR/nope" 2>&1)"
expect "no errinfo path prints nothing" "" "$(_eh_print_failed_output "" 2>&1)"

# --- the container handler prefers the captured output over the raw log tail ---
eval "$(awk '/^(error_handler|_eh_resolve_log|_eh_print_log_tail)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"
_eh_explanation() { echo "explained"; }
_eh_report() { :; }
_eh_write_debug_log() { :; }
_eh_hint_missing_command() { :; }
_eh_hint_node_oom() { :; }
_eh_hint_from_log() { :; }
_is_container_context() { return 0; }
msg_error() { echo "error: $*"; }
handler_output() {
  # error_handler exits, so it runs in a subshell with the state silent() leaves behind.
  (
    export _SILENT_FAILED_RC=1 _SILENT_FAILED_CMD="pnpm install" _SILENT_FAILED_LOG="$LOGFILE"
    # The record only counts for the line it came from.
    _SILENT_FAILED_LINE=$LINENO error_handler 1 "silent pnpm install" 2>&1
  )
}
reset
printf '%s\n' "[INFO] Building" "cargo noise" "ERR_PNPM_OUTDATED_LOCKFILE" >"$LOGFILE"
printf 'EXIT_CODE=1\nLINE=34\nCOMMAND=pnpm install\n--- OUTPUT ---\nERR_PNPM_OUTDATED_LOCKFILE\n' >"$LOGFILE.errinfo"
out="$(handler_output)"
expect "with errinfo the handler shows the command output" 1 "$(printf '%s\n' "$out" | grep -c 'Output of the failing command')"
expect "and leaves out the raw log tail" 0 "$(printf '%s\n' "$out" | grep -c 'Last 20 lines of log')"
rm -f "$LOGFILE.errinfo"
out="$(handler_output)"
expect "without errinfo the raw tail remains" 1 "$(printf '%s\n' "$out" | grep -c 'Last 20 lines of log')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
