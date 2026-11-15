#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^setup_nodejs[(][)] [{]/,/^}/' "$CORE_DIR/lib/runtime.func")"

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

HAVE="node npm jq pnpm"
command() {
  if [[ "${1:-}" == "-v" ]]; then
    [[ " $HAVE " == *" $2 "* ]] && { echo "/usr/bin/$2"; return 0; }
    return 1
  fi
  builtin command "$@"
}

is_tool_installed() { echo 22; }
cleanup_legacy_install() { :; }
ensure_apt_working() { :; }
download_gpg_key() { :; }
cache_installed_version() { :; }
_cs_drop_pm_shim() { :; }
_setup_npm() {
  # shellcheck disable=SC2034  # read by the extracted setup_nodejs
  NPM_SETUP_VERSION="12.2.1"
}
apt() { :; }
apt-get() { :; }
NPM_ROOT="$TEST_DIR/node_modules"
command mkdir -p "$NPM_ROOT/single-file-cli" "$NPM_ROOT/@postlight/parser"
touch "$NPM_ROOT/single-file-cli/package.json" "$NPM_ROOT/@postlight/parser/package.json"
echo "single-file" >"$NPM_ROOT/single-file-cli/bins"
echo "postlight-parser" >"$NPM_ROOT/@postlight/parser/bins"

node() {
  case "$1" in
  -v) echo v22.23.4 ;;
  -e) cat "${3%package.json}bins" ;;
  esac
  return 0
}
corepack() { :; }
npm() {
  case "${1:-}" in
  -v) echo "12.2.1" ;;
  root) echo "$NPM_ROOT" ;;
  list) echo "/usr/lib"; echo "\`-- single-file-cli@2.0.0"; echo "\`-- @postlight/parser@2.2.3" ;;
  install) echo "npm $*" >>"$CALLS" ;;
  esac
  return 0
}
mkdir() { :; }
cd() { [[ "$1" == "/opt" ]] || builtin cd "$@" || return; }

run() {
  : >"$CALLS"
  : >"$LOG"
  NODE_VERSION=22 NODE_MODULE="$1" setup_nodejs
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
HAVE="node npm jq single-file postlight-parser"
run "single-file-cli@latest,@postlight/parser@latest"
expect "a binary named apart from its package is found" "" "$(grep -E '^(warn|error):' "$LOG" | grep -i 'path\|callable')"

HAVE="node npm jq postlight-parser"
run "single-file-cli@latest"
expect "a missing binary reinstalls its package" "1" "$(grep -c 'npm install -g --force single-file-cli@latest' "$CALLS")"
expect "the error names the binary and the package" "1" "$(grep -c 'error: single-file is not callable' "$LOG")"

echo "${passed} passed, ${failed} failed"
((failed == 0))
