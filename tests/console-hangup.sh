#!/usr/bin/env bash
# A closed console (SIGHUP) is not an abort: silent() shields the external
# command of the moment, on_hangup moves the output to the log and carries on,
# a clean install leaves a .done marker, and the host waits for it when
# lxc-attach died with the terminal.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(silent|_cs_shield_hangup|_cs_reattach_output|on_hup_keepalive)[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^(on_hangup|on_exit|_eh_quiet_spinner)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"
eval "$(awk '/^(_pve_wait_for_detached_install|_pve_ct_stopped_by|_pve_ct_gone_during_setup)[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"

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
expect "the hangup is noted in the log" 1 "$(grep -c 'The terminal closed' "$LOG")"
expect "the run knows it is detached" 1 "$(grep -c 'flag=1' "$LOG")"

# A hangup during silent(): on_hangup moved the output inside the call's own
# redirection, bash undid it on return, and the next echo hit the dead terminal.
: >"$LOG"
out="$( (VERBOSE=no; trap on_hangup HUP; silent sh -c 'kill -HUP $PPID; sleep 0.3'; echo "after silent") 2>&1 )"
expect "output after the interrupted call stays off the terminal" "" "$out"
expect "and lands in the log" 1 "$(grep -c 'after silent' "$LOG")"
out="$(echo piped | _cs_shield_hangup cat)"
expect "a piped stdin still reaches the shielded command" "piped" "$out"

# on_hup_keepalive(): tools without catch_errors kept writing to the dead
# terminal, and the next echo or read ended them.
: >"$LOG"
out="$( (unset -f on_hangup; log_msg() { echo "$*"; }; trap on_hup_keepalive HUP; kill -HUP $BASHPID; echo "after hangup"; read -r x || echo "read eof"; echo "flag=${_CS_HANGUP:-}") 2>&1 )"
expect "a tool survives the hangup without on_hangup" "" "$out"
expect "its output lands in the log" 1 "$(grep -c 'after hangup' "$LOG")"
expect "a prompt reads EOF instead of the dead terminal" 1 "$(grep -c 'read eof' "$LOG")"
expect "and the tool knows it is detached" 1 "$(grep -c 'flag=1' "$LOG")"
out="$( (trap on_hup_keepalive HUP; kill -HUP $BASHPID; echo "flag=${_CS_HANGUP:-}") 2>&1 )"
expect "with on_hangup loaded it delegates" 1 "$(grep -c 'The terminal closed' "$LOG")"

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
_CS_INSTALL_STARTED=1793658000
pvenode() {
  if [[ " $* " == *" --output-format json "* ]]; then
    [[ " $* " == *" --since ${_CS_INSTALL_STARTED} "* ]] || return 1
    printf '%s' "${MOCK_TASKS_JSON:-[]}"
    return 0
  fi
  printf '%s\n' "UPID Type ID User Starttime Endtime Status" \
    "UPID:pve:1:vzstart:100:root@pam: vzstart 100 root@pam 2026-10-31 19:37:35 2026-10-31 19:37:36 OK" \
    "UPID:pve:2:vzstop:100:root@pam: vzstop 100 root@pam 2026-10-31 19:40:43 2026-10-31 19:40:44 OK"
}
MOCK_TASKS_JSON='[{"type":"vzstop","upid":"UPID:pve:00034660:021098C2:6AE99CC6:vzstop:100:root@pam:","user":"root@pam"}]'
out="$(_pve_wait_for_detached_install)"
expect "a container stopped from outside ends the wait as an abort" 143 "$?"
expect "it names the recent tasks" 1 "$(grep -c '  vzstop root@pam 2026-10-31 19:40:43 OK' <<<"$out")"
expect "and who ended the install" "[INFO] The install did not fail: vzstop by root@pam ended it" "$(tail -n 1 <<<"$out")"

MOCK_TASKS_JSON='[{"type":"vzstart","upid":"UPID:pve:00034661:021098C3:6AE99CC7:vzstart:100:root@pam:","user":"root@pam"}]'
out="$(_pve_wait_for_detached_install)"
expect "a container that stopped by itself is still unreported" 199 "$?"
kill "$worker" 2>/dev/null

# _pve_ct_gone_during_setup(): a setup step failed; was the container still there?
msg_warn() { echo "warn: $*"; }
msg_error() { echo "error: $*"; }
journalctl() { echo "lxc-start: 100: ../src/lxc/start.c: exited"; }
CT_STATE="status: running"
_pve_ct_gone_during_setup >/dev/null
expect "a running container is not gone" 1 "$?"

CT_STATE="status: stopped"
MOCK_TASKS_JSON='[{"type":"vzshutdown","upid":"UPID:pve:00034662:021098C4:6AE99CC8:vzshutdown:100:root@pam:","user":"root@pam"}]'
out="$(_pve_ct_gone_during_setup; echo "rc=$_CS_SETUP_GONE_RC")"
expect "a shutdown during setup counts as an abort" rc=143 "$(tail -n 1 <<<"$out")"
expect "and says who did it" 1 "$(grep -c 'warn: Container 100 was stopped during its setup (vzshutdown by root@pam)' <<<"$out")"

MOCK_TASKS_JSON='[]'
out="$(_pve_ct_gone_during_setup; echo "rc=$_CS_SETUP_GONE_RC cat=$ERROR_CATEGORY_OVERRIDE")"
expect "a container that stopped by itself is reported as such" "rc=199 cat=proxmox" "$(tail -n 1 <<<"$out")"
expect "with its own journal" 1 "$(grep -c '  lxc-start: 100: ../src/lxc/start.c: exited' <<<"$out")"
unset -f pvenode msg_warn msg_error journalctl
unset MOCK_TASKS_JSON _CS_INSTALL_STARTED

# A redirected call to a shell function makes bash save fd 1 and restore it
# afterwards, which undid the redirect the hangup trap had made. Every message
# after that wrote to the terminal that was gone, and the failed write ended
# the run under errexit.
REDIR="$TEST_DIR/redirected.log"
AFTER="$TEST_DIR/after.log"
inner() { echo "inner"; }
out="$( (
  exec >"$TEST_DIR/orig.log" 2>&1
  _CS_HANGUP=1 _CS_HANGUP_LOG="$AFTER"
  export _CS_HANGUP _CS_HANGUP_LOG
  inner >"$REDIR" 2>&1
  _cs_reattach_output
  echo "after the redirected call"
  readlink /proc/$$/fd/1
) 2>&1 )"
expect "output after a redirected call goes to the hangup log" 1 "$(grep -c 'after the redirected call' "$AFTER" 2>/dev/null)"
expect "and not back to the original target" 0 "$(grep -c 'after the redirected call' "$TEST_DIR/orig.log" 2>/dev/null)"

: >"$AFTER"
( unset _CS_HANGUP; _CS_HANGUP_LOG="$AFTER"; _cs_reattach_output; echo "no hangup" ) >"$TEST_DIR/orig2.log" 2>&1
expect "without a hangup nothing is redirected" 0 "$(grep -c 'no hangup' "$AFTER" 2>/dev/null)"
expect "it stays where it was" 1 "$(grep -c 'no hangup' "$TEST_DIR/orig2.log" 2>/dev/null)"

# The flag outlives the hangup in every script started later. Home Assistant
# answers the Portainer add-on with <<<"y"; dropping that stdin made its prompt
# read EOF and fail the install.
: >"$AFTER"
answer="$( (export _CS_HANGUP=1 _CS_HANGUP_LOG="$AFTER"; _cs_reattach_output; read -r a; printf '%s' "$a" >"$TEST_DIR/answer") <<<"y"; cat "$TEST_DIR/answer" 2>/dev/null)"
expect "a here-string on stdin survives the reattach" y "$answer"
printf 'y\n' >"$TEST_DIR/answer.in"
rm -f "$TEST_DIR/answer"
(export _CS_HANGUP=1 _CS_HANGUP_LOG="$AFTER"; _cs_reattach_output; read -r a; printf '%s' "$a" >"$TEST_DIR/answer") <"$TEST_DIR/answer.in"
expect "so does a file" y "$(cat "$TEST_DIR/answer" 2>/dev/null)"
stdin_after="$( (export _CS_HANGUP=1 _CS_HANGUP_LOG="$AFTER"; _cs_reattach_output; readlink "/proc/$BASHPID/fd/0" >"$TEST_DIR/stdin") </dev/zero; cat "$TEST_DIR/stdin")"
expect "a terminal-like stdin is replaced" /dev/null "$stdin_after"

# The telemetry service decides what counts as a user abort by searching the
# log text, so a word in one of our own messages is enough to file a failure
# as "the operator pressed Ctrl-C". A closed console is not that, and 81 of
# 300 aborted records were this message rather than a person.
CLASSIFIER_TOKENS="sigint ctrl+c ctrl-c sighup aborted by user user abort cancelled by user no changes have been made"
hangup_text="$(awk '/^on_hangup[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")
$(awk '/^_incus_on_hangup[(][)] [{]/,/^}/' "$CORE_DIR/incus/build.func")"
hits=0
while IFS= read -r token; do
  [[ -n "$token" ]] || continue
  if printf '%s' "${hangup_text,,}" | grep -qF "$token"; then
    echo "  token in a hangup message: $token" >&2
    hits=$((hits + 1))
  fi
done <<<"$(printf '%s
' $CLASSIFIER_TOKENS | sed 's/^ *//')"
expect "no hangup message reads as a user abort" 0 "$hits"
expect "both hangup handlers were found" 2 "$(grep -c 'continuing, output follows here' <<<"$hangup_text")"

# The helper the long host commands go through has to survive the signal.
: >"$LOG"
_cs_shield_hangup sh -c 'kill -HUP $$; echo shielded >>"'"$LOG"'"'
expect "a shielded command survives SIGHUP" 0 "$?"
expect "and ran to the end" 1 "$(grep -c shielded "$LOG")"
unshielded_rc=0
{ sh -c 'kill -HUP $$; echo unshielded' >/dev/null 2>&1 || unshielded_rc=$?; } 2>/dev/null
expect "without the shield the same command dies" 129 "$unshielded_rc"

echo "$passed passed, $failed failed"
((failed == 0))
