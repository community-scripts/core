#!/usr/bin/env bash
# A closed console (SIGHUP) is not an abort: silent() shields the external
# command of the moment, on_hangup moves the output to the log and carries on,
# a clean install leaves a .done marker, and the host waits for it when
# lxc-attach died with the terminal.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(silent|_silent_exec)[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^(on_hangup|on_exit|_eh_quiet_spinner)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"
eval "$(awk '/^_pve_wait_for_detached_install[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/install.log"
ROOT="$TEST_DIR/root"
mkdir -p "$ROOT"
passed=0 failed=0
TAB="  "

get_active_logfile() { echo "$LOG"; }
debug_log() { :; }
stop_spinner() { :; }
_is_container_context() { return 0; }
_container_write_failure() { echo "failure $1" >>"$TEST_DIR/failure"; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# silent(): an external command ignores SIGHUP, a function keeps its side effects.
: >"$LOG"
silent sh -c 'kill -HUP $$; echo survived'
expect "an external command under silent survives SIGHUP" 0 "$?"
expect "and finished its work" 1 "$(grep -c survived "$LOG")"
marker() { MARK="set"; }
unset MARK
silent marker
expect "a function keeps its side effects" set "${MARK:-unset}"
silent definitely_missing_command_xyz
expect "a missing command still reports 127" 127 "$?"

# on_hangup(): the run carries on, output moves to the log.
: >"$LOG"
out="$( (trap on_hangup HUP; kill -HUP $BASHPID; echo "after hangup"; echo "flag=${_CS_HANGUP:-}") 2>&1 )"
rc=$?
expect "the shell survives the hangup" 0 "$rc"
expect "nothing more reaches the terminal" "" "$out"
expect "later output lands in the log" 1 "$(grep -c 'after hangup' "$LOG")"
expect "the hangup is noted in the log" 1 "$(grep -c SIGHUP "$LOG")"
expect "the run knows it is detached" 1 "$(grep -c 'flag=1' "$LOG")"

# on_exit(): a clean install leaves .done for the host; a failed one does not.
INSTALL_LOG="$ROOT/.install-abc.log"
export INSTALL_LOG
(trap on_exit EXIT; exit 0)
expect "a clean install leaves a .done marker" 1 "$(ls "$ROOT/.install-abc.done" 2>/dev/null | wc -l)"
rm -f "$ROOT/.install-abc.done"
(trap on_exit EXIT; exit 3)
expect "a failed install leaves no .done marker" 0 "$(ls "$ROOT/.install-abc.done" 2>/dev/null | wc -l)"
expect "but the failure artifact" 1 "$(grep -c 'failure 3' "$TEST_DIR/failure")"
(unset INSTALL_LOG; trap on_exit EXIT; exit 0)
expect "an update run leaves no marker" 0 "$(ls "$ROOT"/.install-*.done 2>/dev/null | wc -l)"

# _pve_wait_for_detached_install(): the host follows the markers of a detached install.
CTID=100 SESSION_ID=abc CT_STATE="status: running"
_CS_HANGUP_POLL=1 _CS_HANGUP_TIMEOUT=3
pct() {
  case "$1" in
  status) echo "$CT_STATE" ;;
  exec)
    shift 3
    case "$1" in
    test) [[ -f "${TEST_DIR}${3}" ]] ;;
    cat) cat "${TEST_DIR}${2}" 2>/dev/null ;;
    kill) command kill "$2" "$3" 2>/dev/null ;;
    esac
    ;;
  esac
}
sleep 30 &
worker=$!
echo "$worker" >"$ROOT/.install-abc.pid"
(sleep 2; : >"$ROOT/.install-abc.done") &
_pve_wait_for_detached_install >/dev/null
expect "a .done marker ends the wait cleanly" 0 "$?"
rm -f "$ROOT/.install-abc.done"

: >"$ROOT/.install-abc.failed"
_pve_wait_for_detached_install >/dev/null
expect "a .failed marker hands the flag to the caller" 1 "$?"
rm -f "$ROOT/.install-abc.failed"

_pve_wait_for_detached_install >/dev/null
expect "no marker before the timeout" 124 "$?"

kill "$worker" 2>/dev/null
wait "$worker" 2>/dev/null
_pve_wait_for_detached_install >/dev/null
expect "a process gone without a marker is reported as such" 199 "$?"

sleep 30 &
worker=$!
echo "$worker" >"$ROOT/.install-abc.pid"
CT_STATE="status: stopped"
_pve_wait_for_detached_install >/dev/null
expect "a stopped container ends the wait" 199 "$?"
kill "$worker" 2>/dev/null

echo "$passed passed, $failed failed"
((failed == 0))
