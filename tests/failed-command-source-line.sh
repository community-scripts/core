#!/usr/bin/env bash
# A failing $STD command is recorded as its line in the script, never with its
# arguments expanded: those carry the passwords and tokens an install passes
# on the command line. Without a readable source line only the program is named.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
MARK="SECRET_MARKER_51c7e2"
LOG="$TEST_DIR/install.log"
SENT="$TEST_DIR/sent.json"
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

mkdir -p "$TEST_DIR/bin"
printf '%s\n' '#!/bin/sh' 'echo "level=error msg=\"cannot reach the instance\""' 'exit 1' >"$TEST_DIR/bin/runner-tool"
chmod +x "$TEST_DIR/bin/runner-tool"

# The container side of an install, as lxc/install.func loads the engine.
cat >"$TEST_DIR/head.sh" <<EOF
source "$CORE_DIR/core/core.func"
source "$CORE_DIR/api/exitcodes.func"
source "$CORE_DIR/api/errorlog.func"
source "$CORE_DIR/core/error_handler.func"
_container_write_failure() { :; }
load_functions
catch_errors
EOF
cat >"$TEST_DIR/helper.func" <<'EOF'
add_runner_user() {
  $STD runner-tool user add --password "$1"
}
EOF
container_run() {
  : >"$LOG"
  rm -f "$LOG.errinfo"
  TELEMETRY_CONTEXT=container SESSION_ID=test INSTALL_LOG="$LOG" TOKEN="$MARK" PATH="$TEST_DIR/bin:$PATH" \
    bash "$@" >"$TEST_DIR/terminal" 2>&1
}
host_send() {
  rm -f "$SENT"
  (
    for part in exitcodes errorlog sysinfo telemetry; do
      # shellcheck disable=SC1090
      source "$CORE_DIR/api/${part}.func"
    done
    # shellcheck disable=SC1091
    source "$CORE_DIR/core/error_handler.func"
    export TELEMETRY_URL=http://telemetry.invalid REPO_SOURCE=ProxmoxVE TELEMETRY_PAYLOAD_VERSION=3 TELEMETRY_TIMEOUT=5 STATUS_TIMEOUT=10
    export DIAGNOSTICS=yes RANDOM_UUID=00000000-0000-4000-8000-000000000000 SESSION_ID=test NSAPP=demo
    export POST_TO_API_DONE=true TELEMETRY_ERRINFO="$LOG.errinfo" INSTALL_LOG="$LOG"
    telemetry_collect_sysinfo() { :; }
    curl() {
      local arg prev=""
      for arg in "$@"; do
        [[ "$prev" == "-d" ]] && printf '%s' "$arg" >"$SENT"
        prev="$arg"
      done
      printf '200'
    }
    post_update_to_api failed 1
  ) >/dev/null 2>&1
}
not_in() { grep -c -- "$MARK" "$1" 2>/dev/null || true; }
recorded() { sed -n 's/^COMMAND=//p' "$LOG.errinfo" 2>/dev/null; }
sent_command() { grep -c -F "\"failed_command\": \"${1//\"/\\\"}\"," "$SENT" 2>/dev/null || true; }

# --- the failing line of the install script ---
line='$STD runner-tool register --instance "https://git.example.net" --token "$TOKEN"'
{ cat "$TEST_DIR/head.sh"; echo 'msg_info "Registering runner"'; echo "$line"; } >"$TEST_DIR/install.sh"
container_run "$TEST_DIR/install.sh"
rc=$?
want='runner-tool register --instance "https://git.example.net" --token "$TOKEN"'
expect "the install fails with the command's code" 1 "$rc"
expect "the capture records the source line" "$want" "$(recorded)"
expect "the capture does not hold the token" 0 "$(not_in "$LOG.errinfo")"
expect "the capture still holds the output" 1 "$(grep -c 'cannot reach the instance' "$LOG.errinfo")"
expect "the install log names the source line" 1 "$(grep -cF "while executing command $want" "$LOG")"
expect "the install log does not hold the token" 0 "$(not_in "$LOG")"
host_send
expect "a payload is sent" yes "$([[ -s "$SENT" ]] && echo yes || echo no)"
expect "failed_command is the source line" 1 "$(sent_command "$want")"
expect "the payload does not hold the token" 0 "$(not_in "$SENT")"

# --- a helper from a sourced file, called with the secret ---
{ cat "$TEST_DIR/head.sh"; echo "source \"$TEST_DIR/helper.func\""; echo 'add_runner_user "$TOKEN"'; } >"$TEST_DIR/install.sh"
container_run "$TEST_DIR/install.sh"
want='runner-tool user add --password "$1"'
expect "a helper's capture records the helper's line" "$want" "$(recorded)"
expect "and not the password" 0 "$(not_in "$LOG.errinfo")"
expect "nor does the install log" 0 "$(not_in "$LOG")"

# --- no source line to read back: a script piped into bash ---
{ cat "$TEST_DIR/head.sh"; echo "$line"; } >"$TEST_DIR/install.sh"
container_run -s <"$TEST_DIR/install.sh"
want='runner-tool (arguments withheld)'
expect "without a source line the program is named" "$want" "$(recorded)"
expect "the capture does not hold the token" 0 "$(not_in "$LOG.errinfo")"
expect "the install log does not hold the token" 0 "$(not_in "$LOG")"
host_send
expect "failed_command names only the program" 1 "$(sent_command "$want")"
expect "the payload does not hold the token" 0 "$(not_in "$SENT")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
