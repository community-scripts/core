#!/usr/bin/env bash
# An interrupted `npm install -g npm@latest` leaves nodejs installed without
# npm. --only-upgrade is then a no-op and _setup_npm returns early, so the
# same-version branch reported success while every module failed (#182).
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

# Which binaries exist. The code under test only ever asks via `command -v`, so
# shadowing the builtin keeps this box's real npm out of the run.
HAVE="node jq"
command() {
  if [[ "${1:-}" == "-v" ]]; then
    [[ " $HAVE " == *" $2 "* ]] && { echo "/usr/bin/$2"; return 0; }
    return 1
  fi
  builtin command "$@"
}

# Node 22 installed, Node 22 wanted: the same-version branch.
is_tool_installed() { echo 22; }
cleanup_legacy_install() { :; }
ensure_apt_working() { :; }
download_gpg_key() { :; }
cache_installed_version() { :; }
_cs_drop_pm_shim() { :; }
_setup_npm() {
  echo "_setup_npm" >>"$CALLS"
  # shellcheck disable=SC2034  # read by the extracted setup_nodejs
  NPM_SETUP_VERSION="12.2.1"
}
_apt_record() {
  echo "$*" >>"$CALLS"
  # A NodeSource nodejs ships npm, so the reinstall brings it back.
  [[ "$*" == *--reinstall*nodejs* && "${MOCK_REINSTALL_RESTORES:-1}" == 1 ]] && HAVE="$HAVE npm"
  return 0
}
apt() { _apt_record "apt $*"; }
apt-get() { _apt_record "apt-get $*"; }
node() { [[ "$1" == "-v" ]] && echo v22.23.4; return 0; }
corepack() { :; }
npm() {
  case "${1:-}" in
  -v) echo "12.2.1" ;;
  list) return 1 ;;
  install)
    [[ -n "${MOCK_FAIL_MODULE:-}" && "$*" == *"$MOCK_FAIL_MODULE"* ]] && return 1
    return "${MOCK_NPM_INSTALL_RC:-0}"
    ;;
  *) return 0 ;;
  esac
}
mkdir() { :; }
cd() { [[ "$1" == "/opt" ]] || builtin cd "$@" || return; }

run() {
  : >"$CALLS"
  : >"$LOG"
  NODE_VERSION=22 setup_nodejs
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

# -- npm went missing, the reinstall brings it back -------------------------
HAVE="node jq"
run
rc=$?
expect "a missing npm does not fail the update" 0 "$rc"
expect "the loss is reported" 1 "$(grep -c 'warn: npm is missing - reinstalling nodejs' "$LOG")"
expect "nodejs is reinstalled" 1 "$(grep -c 'install -y --reinstall nodejs' "$CALLS")"
expect "_setup_npm runs once npm is back" 1 "$(grep -c '^_setup_npm$' "$CALLS")"
expect "the branch still reports success" 1 "$(grep -c 'ok: Update Node.js 22 (npm 12.2.1)' "$LOG")"

# -- the reinstall does not bring npm back (Debian's separate npm package) ---
HAVE="node jq"
MOCK_REINSTALL_RESTORES=0 run
rc=$?
expect "an unrecoverable npm fails the function" 1 "$rc"
expect "and says so" 1 "$(grep -c 'error: Could not restore npm' "$LOG")"
expect "without claiming the update worked" 0 "$(grep -c 'ok: Update Node.js' "$LOG")"
expect "_setup_npm is not reached" 0 "$(grep -c '^_setup_npm$' "$CALLS")"

# -- npm present: nothing is reinstalled ------------------------------------
HAVE="node jq npm"
run
rc=$?
expect "a healthy npm still succeeds" 0 "$rc"
expect "no reinstall is attempted" 0 "$(grep -c -- '--reinstall' "$CALLS")"
expect "nothing is warned about" 0 "$(grep -c 'npm is missing' "$LOG")"

# -- a module that fails install and restore is counted once ----------------
HAVE="node jq npm"
MOCK_NPM_INSTALL_RC=1 NODE_MODULE=yarn run
expect "the failed module is named, not the whole request" 1 \
  "$(grep -c 'warn: 1 Node.js module(s) failed: yarn' "$LOG")"
expect "it is not counted twice" 0 "$(grep -c '2 Node.js module(s) failed' "$LOG")"
expect "the restore attempt is still reported" 1 \
  "$(grep -c 'error: yarn is not callable and could not be restored' "$LOG")"

# -- only the modules that failed are listed --------------------------------
HAVE="node jq npm yarn"
MOCK_FAIL_MODULE=pnpm NODE_MODULE=yarn,pnpm run
expect "a module that installed stays out of the list" 1 \
  "$(grep -c 'warn: 1 Node.js module(s) failed: pnpm' "$LOG")"

# -- two genuinely broken modules are both named ----------------------------
HAVE="node jq npm"
MOCK_NPM_INSTALL_RC=1 NODE_MODULE=yarn,pnpm run
expect "both are listed, each once" 1 \
  "$(grep -c 'warn: 2 Node.js module(s) failed: yarn pnpm' "$LOG")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
