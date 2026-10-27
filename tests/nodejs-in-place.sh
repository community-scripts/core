#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(setup_nodejs|_nodejs_in_place_simulate)[(][)] [{]/,/^}/' "$CORE_DIR/lib/runtime.func")"
eval "$(awk '/^_purge_is_safe[(][)] [{]/,/^}/' "$CORE_DIR/lib/system.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CALLS="$TEST_DIR/calls"
LOG="$TEST_DIR/log"
passed=0 failed=0

export STD=""
msg_info() { echo "info: $*" >>"$LOG"; }
msg_ok() { echo "ok: $*" >>"$LOG"; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
is_tool_installed() { echo "${MOCK_CURRENT:-20}"; }
cleanup_legacy_install() { :; }
ensure_apt_working() { :; }
ensure_dependencies() { :; }
download_gpg_key() { :; }
remove_old_tool_version() { echo "purge $1" >>"$CALLS"; }
prepare_repository_setup() { :; }
manage_tool_repository() { echo "repo $2" >>"$CALLS"; }
cleanup_old_repo_files() { echo "drop repo $1" >>"$CALLS"; }
install_packages_with_retry() { echo "install $*" >>"$CALLS"; }
verify_tool_version() { :; }
cache_installed_version() { :; }
_setup_npm() { :; }
dpkg() { [[ "$1" == "-l" ]] && printf '%s\n' "${MOCK_DPKG:-ii  nodejs  20.19.2+dfsg-1}"; return 0; }
dpkg-query() { echo "${MOCK_NODE_DEB:-20.19.2+dfsg-1+deb13u3}"; }
apt() { echo "apt $*" >>"$CALLS"; }
apt-get() {
  case "$*" in
  "-s purge"*) printf '%s\n' "${MOCK_PURGE:-}" ;;
  "-s install"*) printf '%s\n' "${MOCK_SIM:-Inst nodejs [20.19.2] (22.23.4-1nodesource1)}" ;;
  esac
}
node() { echo v22.23.4; }
npm() { [[ "$1" == "-v" ]] && echo 11.21.1; return 0; }
corepack() { :; }
mkdir() { :; }
cd() { [[ "$1" == "/opt" ]] || builtin cd "$@" || return; }

run() {
  : >"$CALLS"
  : >"$LOG"
  local rc=0
  NODE_VERSION="${TARGET:-22}" setup_nodejs >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$CALLS" "$LOG" >&2
    failed=$((failed + 1))
  fi
}
has() { grep -cxF -- "$1" "$CALLS"; }

DEPENDENT=$'Purg nodejs [20.19.2]\nPurg thelounge [4.4.3]\nPurg libnode115 [20.19.2]'

expect "nothing depends on nodejs: purge" 0 "$(MOCK_PURGE='Purg nodejs [20.19.2]' run)"
expect "  the old version is purged" 1 "$(has 'purge nodejs')"
expect "  Debian's packages are removed" 1 "$(grep -c '^apt purge -y nodejs' "$CALLS")"

expect "an app depends on nodejs: in place" 0 "$(MOCK_PURGE="$DEPENDENT" run)"
expect "  nothing is purged" 0 "$(grep -c 'purge' "$CALLS")"
expect "  nodejs is installed over the old one" 1 "$(has 'install nodejs')"

expect "in place would remove the app: refused" 1 "$(MOCK_PURGE="$DEPENDENT" MOCK_SIM=$'Remv thelounge [4.4.3]\nInst nodejs [20.19.2] (22.23.4-1nodesource1)' run)"
expect "  nodejs is not installed" 0 "$(has 'install nodejs')"
expect "  the reason names the app" 1 "$(grep -c 'would remove thelounge' "$LOG")"
expect "  Debian nodejs: the new repository is dropped" 1 "$(has 'drop repo nodesource')"

expect "refused over a NodeSource build: old repository back" 1 "$(MOCK_PURGE="$DEPENDENT" MOCK_NODE_DEB=20.20.2-1nodesource1 MOCK_SIM='Remv thelounge [4.4.3]' run)"
expect "  repository 20 is restored" 1 "$(has 'repo 20')"

expect "Debian's npm and node-* packages may go" 0 "$(MOCK_PURGE="$DEPENDENT" MOCK_SIM=$'Remv npm [9.2.0]\nRemv node-acorn [8.8.1]\nRemv libnode115 [20.19.2]' run)"

expect "downgrade with a dependent: refused" 1 "$(MOCK_CURRENT=24 MOCK_PURGE="$DEPENDENT" run)"
expect "  no repository is touched" 0 "$(grep -c '^repo' "$CALLS")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
