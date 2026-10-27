#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_SOURCE=ProxmoxVE
for part in exitcodes errorlog sysinfo telemetry; do
  # shellcheck disable=SC1090
  source "$CORE_DIR/api/${part}.func"
done
eval "$(awk '/^_eh_(explanation|tools_for|command_is|command_word)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"
TELEMETRY_PAYLOAD_VERSION=3 TELEMETRY_TIMEOUT=5 STATUS_TIMEOUT=10

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
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
json_field() {
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$2" '.[$k] | tostring' "$1"
  else
    python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(v if not isinstance(v,bool) else str(v).lower())' "$1" "$2"
  fi
}
reset() {
  : >"$LOG"
  rm -f "$SENT" "$TEST_DIR"/*.errinfo
  unset TELEMETRY_ERRINFO FAILED_COMMAND FAILED_LINE FAILED_FUNCTION CS_STEP CS_STEP_DONE CS_ERROR_MSG ERROR_CATEGORY_OVERRIDE
  unset TM_ERR_CODE TM_ERR_EXPLANATION
  POST_TO_API_DONE=true POST_UPDATE_DONE=false
}
_tm_send() { printf '%s' "$1" >"$SENT"; }
telemetry_collect_sysinfo() { :; }
DIAGNOSTICS=yes RANDOM_UUID=00000000-0000-4000-8000-000000000000 SESSION_ID=test NSAPP=demo
BUILD_LOG="$LOG" INSTALL_LOG="$TEST_DIR/none.log"

# --- noise filter ---
printf '%s\n' \
  'Get:1 http://deb.debian.org/debian trixie InRelease [140 kB]' \
  'Setting up libssl3t64:amd64 (3.5.1-1) ...' \
  'update-alternatives: using /usr/bin/node to provide /usr/bin/js (js) in auto mode' \
  '     0K ........ ........ ........ ........ 25% 8.29M 11s' \
  '+ umask 022' \
  '  WARNING: You have not turned on protection against thin pools running out of space.' \
  'E: Unable to locate package foo' \
  '[2026-01-01 10:00:00] Setup uv 0.9.5 from 192.168.1.101' >"$LOG"
out="$(_tm_clean_log <"$LOG")"
expect "progress chatter is dropped" 2 "$(wc -l <<<"$out" | tr -d ' ')"
expect "the apt error survives" 1 "$(grep -c '^E: Unable to locate package foo$' <<<"$out")"
expect "versions survive, addresses do not" "[2026-01-01 10:00:00] Setup uv 0.9.5 from 192.x.x.x" "$(tail -n1 <<<"$out")"

# --- step scoping ---
printf '%s\n' '[2026-01-01 10:00:00] [INFO] Installing Dependencies' 'old output' \
  '[2026-01-01 10:00:05] [OK] Installed Dependencies' \
  '[2026-01-01 10:00:06] [INFO] Setting up Demo' 'curl: (22) The requested URL returned error: 404' >"$LOG"
expect "only the failing step is kept" "[2026-01-01 10:00:06] [INFO] Setting up Demo|curl: (22) The requested URL returned error: 404" "$(_tm_focus <"$LOG" | paste -sd'|')"

# --- a container failure, read by the host ---
reset
printf '%s\n' 'EXIT_CODE=7' 'LINE=24' 'COMMAND=setup_uv' 'FUNCTION=' 'STEP=Setup uv' \
  'MESSAGE=Failed to download uv from https://github.com/astral-sh/uv/releases/x.tar.gz' 'PHASE=container' \
  '--- OUTPUT ---' '[2026-01-01 10:00:06] [INFO] Setup uv' 'curl: (7) Failed to connect to github.com port 443' >"$TEST_DIR/ct.errinfo"
TELEMETRY_ERRINFO="$TEST_DIR/ct.errinfo"
CS_ERROR_MSG="Installation failed in container 100 (exit code: 7)" CS_STEP="Starting install"
post_update_to_api failed 7
expect "the container's message wins over the host's" "Failed to download uv from https://github.com/astral-sh/uv/releases/x.tar.gz" "$(json_field "$SENT" error_message)"
expect "the container's step" "Setup uv" "$(json_field "$SENT" error_step)"
expect "phase" container "$(json_field "$SENT" error_phase)"
expect "failed command" setup_uv "$(json_field "$SENT" failed_command)"
expect "payload version" 3 "$(json_field "$SENT" payload_version)"
expect "header" "exit_code=7 | setup_uv exited with status 7 | step: Setup uv | at line 24: setup_uv" "$(json_field "$SENT" error | head -n1)"

# --- a capture for an earlier failure is not used ---
reset
printf '%s\n' 'EXIT_CODE=100' 'LINE=3' 'COMMAND=apt-get install -y foo' 'PHASE=host' '--- OUTPUT ---' 'E: old' >"$LOG.errinfo"
printf '%s\n' '[2026-01-01 10:00:00] [INFO] Creating container' 'unable to create CT 101 - storage full' >"$LOG"
CS_ERROR_MSG="Container creation failed" CS_STEP="Creating container"
post_update_to_api failed 209
expect "mismatched capture ignored" 209 "$(json_field "$SENT" exit_code)"
expect "host message" "Container creation failed" "$(json_field "$SENT" error_message)"
expect "host phase" host "$(json_field "$SENT" error_phase)"
expect "step output instead" 1 "$(json_field "$SENT" error | grep -c 'storage full')"

# --- status mapping ---
reset
post_update_to_api failed 130
expect "Ctrl-C is an abort" aborted "$(json_field "$SENT" status)"
expect "an abort sends no message" "" "$(json_field "$SENT" error_message)"
reset
post_update_to_api done none
expect "done is success" success "$(json_field "$SENT" status)"
expect "success carries no error" "" "$(json_field "$SENT" error)"
reset
post_update_to_api failed ""
expect "a lost code is 199" 199 "$(json_field "$SENT" exit_code)"
reset
POST_UPDATE_DONE=true
post_update_to_api failed 1
expect "one terminal event per execution" no "$([[ -f "$SENT" ]] && echo yes || echo no)"

# --- JSON stays valid with awkward text ---
reset
CS_ERROR_MSG=$'quote " backslash \\ tab \t done' CS_STEP='Step "x"'
printf '%s\n' '[2026-01-01 10:00:00] [INFO] Step "x"' 'line with "quotes"' >"$LOG"
post_update_to_api failed 1
expect "message with quotes and backslashes round-trips" 'quote " backslash \ tab done' "$(json_field "$SENT" error_message)"

# --- tools and add-ons carry the same fields ---
reset
CS_ERROR_MSG="No LXC containers found" CS_STEP="Scanning containers"
post_tool_to_api demo-tool failed 234
expect "tool failures stay failures" failed "$(json_field "$SENT" status)"
expect "tool type" pve "$(json_field "$SENT" type)"
expect "tool message" "No LXC containers found" "$(json_field "$SENT" error_message)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
