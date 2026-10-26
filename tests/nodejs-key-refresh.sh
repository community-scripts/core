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
# Node 24 installed, Node 24 wanted: the same-major update path.
is_tool_installed() { echo 24; }
cleanup_legacy_install() { :; }
ensure_apt_working() { echo "ensure_apt_working" >>"$CALLS"; }
download_gpg_key() {
  echo "download_gpg_key $*" >>"$CALLS"
  return "${MOCK_KEY_RC:-0}"
}
apt-get() { echo "apt-get $*" >>"$CALLS"; }
apt() { echo "apt $*" >>"$CALLS"; }
node() { [[ "$1" == "-v" ]] && echo v24.13.0; return 0; }
corepack() { :; }
pnpm() { :; }
yarn() { :; }
npm() { [[ "$1" == "-v" ]] && echo 11.6.0; return 0; }
_setup_npm() { :; }
cache_installed_version() { :; }
mkdir() { :; }
cd() { [[ "$1" == "/opt" ]] || builtin cd "$@" || return; }

run() {
  : >"$CALLS"
  : >"$LOG"
  NODE_VERSION=24 setup_nodejs
}
line_of() { grep -nF -- "$1" "$CALLS" | head -n1 | cut -d: -f1; }
before() { [[ -n "$1" && -n "$2" ]] && ((${1} < ${2})) && echo yes || echo no; }
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

run
expect "same-major update succeeds" 0 "$?"
expect "the NodeSource key is refreshed" "download_gpg_key https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key /etc/apt/keyrings/nodesource.gpg dearmor" "$(grep -F download_gpg_key "$CALLS")"
expect "the refresh happens before apt update" yes "$(before "$(line_of download_gpg_key)" "$(line_of ensure_apt_working)")"
expect "the refresh happens before the upgrade" yes "$(before "$(line_of download_gpg_key)" "$(line_of 'apt-get install -y --only-upgrade nodejs')")"

MOCK_KEY_RC=7 run
expect "a failed key download does not abort the update" 0 "$?"
expect "the upgrade still runs" 1 "$(grep -c 'apt-get install -y --only-upgrade nodejs' "$CALLS")"
expect "the failed refresh is reported" 1 "$(grep -c 'warn: Could not refresh the NodeSource signing key' "$LOG")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
