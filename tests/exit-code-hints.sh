#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(explain_exit_code|categorize_error)[(][)] [{]/,/^}/' "$CORE_DIR/api/exitcodes.func")"
eval "$(awk '/^_eh_(hint_from_log|explanation|tools_for|command_is|command_word)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"
eval "$(awk '/^(_tm_explain|_tm_one_line|_tm_error_context|_tm_format_error|build_error_string)[(][)] [{]/,/^}/' "$CORE_DIR/api/errorlog.func")"
_tm_find_errinfo() { return 1; }
get_error_log() { :; }
unset CS_STEP CS_STEP_DONE CS_ERROR_MSG FAILED_FUNCTION

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/log"
WARN="$TEST_DIR/warn"
passed=0 failed=0
_eh_warn() { echo "$1" >>"$WARN"; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# Exit status 1 is the command's own verdict; errno 1 (EPERM) is something else.
expect "exit 1 is not explained as EPERM" 0 "$(explain_exit_code 1 | grep -c 'Operation not permitted')"
expect "no table entry for 1-3 asks the reader to look elsewhere" 0 "$(for c in 1 2 3; do explain_exit_code "$c"; done | grep -ci 'says why')"

# A tool-specific meaning holds only for that tool; everything else names the program.
expect "cargo 101 is not an APT error" "cargo exited with status 101" "$(_eh_explanation 101 'cargo build --release')"
expect "apt-get 101 keeps the APT text" APT "$(_eh_explanation 101 'apt-get install -y jq' | cut -d: -f1)"
expect "a core wrapper returning 7 is not curl" "fetch_and_deploy_gh_release exited with status 7" "$(_eh_explanation 7 'fetch_and_deploy_gh_release app owner/repo')"
expect "curl 7 with a path keeps the curl text" curl "$(_eh_explanation 7 '/usr/bin/curl -fsSL https://x' | cut -d: -f1)"
expect "git 128 is a git fatal error" git "$(_eh_explanation 128 'git clone https://x' | cut -d: -f1)"
expect "pnpm 128 is not" "pnpm exited with status 128" "$(_eh_explanation 128 'pnpm build')"
expect "node 243 keeps the Node text" Node.js "$(_eh_explanation 243 'node server.js' | cut -d: -f1)"
expect "python 243 does not" "python3 exited with status 243" "$(_eh_explanation 243 'python3 app.py')"
expect "core codes stay as they are" Proxmox "$(_eh_explanation 209 '' | cut -d: -f1)"
expect "unprefixed codes stay as they are" "Command not found" "$(_eh_explanation 127 'foo')"
expect "systemctl 5 is a missing unit" "Systemd: unit not found" "$(_eh_explanation 5 'systemctl start portainer')"
expect "exit 1 names the program" "uv exited with status 1" "$(_eh_explanation 1 'uv run -- python manage.py migrate')"
expect "assignments and \$STD are skipped" "npm exited with status 1" "$(_eh_explanation 1 'NODE_ENV=production $STD /usr/bin/npm ci')"
expect "grep without a match" "grep found no match" "$(_eh_explanation 1 'grep -q foo /etc/hosts')"
expect "arithmetic that evaluates to 0" "Arithmetic expression evaluated to 0" "$(_eh_explanation 1 '((attempt++))')"
expect "a failed test" "Test condition was false" "$(_eh_explanation 1 '[[ -f /opt/app/.env ]]')"
expect "a command substitution" "Command substitution exited with status 1" "$(_eh_explanation 1 'RELEASE=$(curl -fsSL "$URL" | grep -oP x | head -n1)')"
expect "an unresolved return" "Exit status 7" "$(_eh_explanation 7 'return 7')"

# The telemetry summary goes through the same guard when the command is known.
expect "the summary does not call systemctl 5 a proxy error" "exit_code=5 | Systemd: unit not found | at line 76: systemctl start portainer" "$(FAILED_COMMAND='systemctl start portainer' FAILED_LINE=76 build_error_string 5)"
expect "pct exec 255 is not a DPKG error" "exit_code=255 | pct exited with status 255 | at line 12: pct exec 100 -- ip a" "$(FAILED_COMMAND='pct exec 100 -- ip a' FAILED_LINE=12 build_error_string 255)"
expect "step and function join the header" "exit_code=7 | Exit status 7 | step: Setting up Grafana Repository | in setup_deb822_repo | at line 24: return 7" "$(CS_STEP='Setting up Grafana Repository' FAILED_FUNCTION=setup_deb822_repo FAILED_COMMAND='return 7' FAILED_LINE=24 build_error_string 7)"
expect "a finished step is named as such" "exit_code=64 | Missing or invalid input (a required setting was not given) | step: after Updated Container OS" "$(CS_STEP_DONE='Updated Container OS' FAILED_COMMAND= build_error_string 64)"
expect "apt 100 keeps the APT text" APT "$(FAILED_COMMAND='apt install -y grafana' FAILED_LINE=31 build_error_string 100 | cut -d'|' -f2 | cut -d: -f1 | tr -d ' ')"
expect "without a command the table stands" "exit_code=255 | DPKG: Fatal internal error" "$(FAILED_COMMAND= build_error_string 255)"

# The category follows the tool where the code is shared.
expect "systemctl is a service failure" service "$(categorize_error 5 'systemctl start portainer')"
expect "pct exec is a Proxmox failure" proxmox "$(categorize_error 255 'pct exec 100 -- ip a')"
expect "a kill stays a resource failure whatever ran" resource "$(categorize_error 137 'pct exec 100 -- cargo build')"
expect "apt keeps its category" dependency "$(categorize_error 100 'apt install -y grafana')"
expect "an abort stays an abort" user_aborted "$(categorize_error 130 'systemctl start x')"
expect "no command: the table" shell "$(FAILED_COMMAND= categorize_error 1)"

: >"$WARN"
printf '%s\n' 'Scope: all 36 workspace projects' ' ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with "frozen-lockfile" because pnpm-lock.yaml is not up to date with <ROOT>/server/package.json' >"$LOG"
_eh_hint_from_log "$LOG"
expect "a stale pnpm lockfile is named" 1 "$(grep -c 'lockfile does not match' "$WARN")"
expect "the fallback is suggested" 1 "$(grep -c 'no-frozen-lockfile' "$WARN")"

: >"$WARN"
printf '%s\n' '[OK] Git DNS: github.com:(ok)' '[ERROR] in line 34: exit code 1' >"$LOG"
_eh_hint_from_log "$LOG"
expect "the network check line raises no hint" 0 "$(wc -l <"$WARN" | tr -d ' ')"

# The host classifies the combined log itself; a bare DNS used to match the network check line.
expect "pve host grep no longer matches the word DNS alone" 0 "$(grep -c 'resolve|DNS|' "$CORE_DIR/pve/backend.func")"
expect "incus host grep no longer matches the word DNS alone" 0 "$(grep -c 'resolve|DNS|' "$CORE_DIR/incus/backend.func")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
