#!/usr/bin/env bash
# NODE_MODULE="$(jq -r .packageManager package.json)" passes pnpm@12.14.0+sha512.<hex>.
# npm list prints 12.14.0, so the pin never matched and pnpm was reinstalled on
# every update.
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

# Node 22 installed, Node 22 wanted, pnpm 12.14.0 already global.
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
node() { [[ "$1" == "-v" ]] && echo v22.23.4; return 0; }
corepack() { :; }
npm() {
  case "${1:-}" in
  -v) echo "12.2.1" ;;
  list) echo "/usr/lib"; echo "\`-- pnpm@12.14.0" ;;
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

run "pnpm@12.14.0+sha512.0123abcd"
expect "the installed pin with a hash is not reinstalled" "" "$(cat "$CALLS")"

run "pnpm@12.14.0"
expect "the installed pin without a hash is not reinstalled" "" "$(cat "$CALLS")"

run "pnpm@12.15.0+sha512.0123abcd"
expect "a new pin with a hash installs that version" "npm install -g pnpm@12.15.0" "$(head -n1 "$CALLS")"

echo "${passed} passed, ${failed} failed"
((failed == 0))
