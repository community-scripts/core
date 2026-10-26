#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# The MongoDB helpers and the purge guard; the rest of the engine is stubbed.
eval "$(awk '/^(setup_mongodb|_mongodb_in_place_precheck|_mongodb_in_place_simulate|mongodb_get_fcv|mongodb_set_fcv)\(\) \{/,/^}/' "$CORE_DIR/lib/db.func")"
eval "$(awk '/^_purge_is_safe\(\) \{/,/^}/' "$CORE_DIR/lib/system.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/calls"
# shellcheck disable=SC2034  # read by the eval'd helpers
STD="" YW=""
passed=0 failed=0 case_failed=0 case_name=""

log() { printf '%s\n' "$*" >>"$LOG"; }
msg_info() { log "info: $*"; }
msg_ok() { log "ok: $*"; }
msg_warn() { log "warn: $*"; }
msg_error() { log "error: $*"; }
msg_custom() { log "custom: $3"; }
get_os_info() { case "$1" in id) echo debian ;; codename) echo bookworm ;; esac; }
is_tool_installed() { [[ -n "${MOCK_INSTALLED:-}" ]] && echo "$MOCK_INSTALLED"; }
ensure_apt_working() { :; }
upgrade_packages_with_retry() { log "upgrade $*"; }
install_packages_with_retry() { log "install $*"; }
remove_old_tool_version() { log "purge $*"; }
cleanup_orphaned_sources() { :; }
prepare_repository_setup() { :; }
manage_tool_repository() { log "repo $2"; }
cache_installed_version() { log "cache $2"; }
verify_tool_version() { :; }
safe_service_restart() { log "restart $1"; }
systemctl() { :; }
mkdir() { :; }
chown() { :; }
apt() { :; }
uname() { case "$1" in -m) echo x86_64 ;; -r) echo 6.1.0 ;; esac; }
mongod() { echo "db version v${MOCK_MONGOD:-7.0.22}"; }
mongosh() {
  log "mongosh $*"
  case "$*" in
  *getParameter*) [[ -n "${MOCK_FCV:-}" ]] && echo "$MOCK_FCV" || return 1 ;;
  *) return 0 ;;
  esac
}
apt-get() {
  case "$*" in
  "-s purge"*) printf '%s\n' "${MOCK_PURGE:-}" ;;
  "-s install"*)
    printf '%s\n' "${MOCK_SIM:-Inst mongodb-org [7.0.22] (8.0.3)}"
    return "${MOCK_SIM_RC:-0}"
    ;;
  esac
}

begin() {
  case_name="$1" case_failed=0
  : >"$LOG"
  local rc=0
  MONGO_VERSION="${TARGET:-8.0}" setup_mongodb >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "$2" ]] || { echo "  rc=$rc, expected $2"; case_failed=1; }
}
expect() { grep -qF -- "$1" "$LOG" || { echo "  missing: $1"; case_failed=1; }; }
reject() { ! grep -qF -- "$1" "$LOG" || { echo "  unexpected: $1"; case_failed=1; }; }
before() {
  local a b
  a=$(grep -nF -- "$1" "$LOG" | head -n1 | cut -d: -f1)
  b=$(grep -nF -- "$2" "$LOG" | head -n1 | cut -d: -f1)
  [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]] || { echo "  order: '$1' must come before '$2'"; case_failed=1; }
}
end() {
  if ((case_failed)); then
    echo "FAIL $case_name"
    sed 's/^/    /' "$LOG"
    failed=$((failed + 1))
  else
    echo "PASS $case_name"
    passed=$((passed + 1))
  fi
}

MOCK_INSTALLED="" begin "fresh install" 0
expect "repo 8.0"; expect "install mongodb-org"; reject "purge"; reject "mongosh"
end

MOCK_INSTALLED="8.0" begin "same series only takes patch updates" 0
expect "upgrade mongodb-org"; reject "repo"; reject "install mongodb-org"
end

MOCK_INSTALLED="7.0" MOCK_PURGE=$'Purg mongodb-org [7.0.22]\nPurg mongodb-org-server [7.0.22]' begin "purge when nothing depends on it" 0
expect "purge mongodb"; expect "repo 8.0"; expect "install mongodb-org"; reject "setFeatureCompatibilityVersion"
end

MOCK_INSTALLED="7.0" MOCK_PURGE=$'Purg mongodb-org-server [7.0.22]\nRemv omadac [6.2.10.17]' MOCK_FCV="7.0" begin "in place when a package depends on it" 0
reject "purge mongodb"; expect "repo 8.0"; expect "install mongodb-org"
expect "setFeatureCompatibilityVersion: '8.0', confirm: true"; expect "custom: Apps that run their own mongod"
end

MOCK_INSTALLED="7.0" MOCK_PURGE="Remv omadac [6.2.10.17]" MOCK_FCV="6.0" begin "data still at the older fcv is raised first" 0
expect "setFeatureCompatibilityVersion: '7.0', confirm: true"
before "setFeatureCompatibilityVersion: '7.0'" "install mongodb-org"
before "install mongodb-org" "setFeatureCompatibilityVersion: '8.0'"
end

MOCK_INSTALLED="6.0" MOCK_PURGE="Remv omadac [6.2.10.17]" begin "refuse a two-major jump" 1
expect "needs 7.0 first"; reject "install mongodb-org"; reject "repo"
end

MOCK_INSTALLED="8.0" TARGET="7.0" MOCK_PURGE="Remv omadac [6.2.10.17]" begin "refuse a downgrade" 1
expect "cannot be downgraded"; reject "install mongodb-org"
end

MOCK_INSTALLED="7.0" MOCK_PURGE="Remv omadac [6.1.0]" MOCK_FCV="7.0" MOCK_SIM=$'Inst mongodb-org-server [7.0.22] (8.0.3)\nRemv omadac [6.1.0]' begin "refuse when apt would remove the app" 1
expect "would remove: omadac"; reject "install mongodb-org"
before "repo 8.0" "repo 7.0"
end

MOCK_INSTALLED="7.0" MOCK_PURGE="Remv omadac [6.1.0]" MOCK_FCV="7.0" MOCK_SIM="E: Unable to correct problems, you have held broken packages." MOCK_SIM_RC=100 begin "abort when apt refuses the upgrade" 1
expect "cannot upgrade mongodb-org in place"; expect "repo 7.0"; reject "install mongodb-org"
end

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
