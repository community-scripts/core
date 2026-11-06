#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^_FORGE_JQ_VKEY_DEF=/,/^_FORGE_JQ_VKEY=/p' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^_forge_(descriptor|strip_v|is_current|highest_version|same_shape|stable_filter)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^(check_for_release|_forge_previous_version)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^on_exit[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
LOG="$TEST_DIR/log"
passed=0 failed=0

# jq on Windows prints CRLF; mapfile -t keeps the CR and the pin compare is exact.
jq() { command jq "$@" | tr -d '\r'; }
msg_info() { :; }
msg_ok() { echo "ok: $*" >>"$LOG"; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
ensure_dependencies() { :; }
getent() { return 0; }
_forge_designated_release() { return 1; }
# The list for the normal path, the single tag for the pinned one.
_forge_http_get() {
  if [[ "$2" == */releases/tags/* ]]; then
    printf '%s' '{"tag_name":"v2.16.0","prerelease":false,"draft":false}' >"$3"
  else
    printf '%s' '[{"tag_name":"v2.16.0","prerelease":false,"draft":false},{"tag_name":"v2.15.1","prerelease":false,"draft":false}]' >"$3"
  fi
}
_is_container_context() { return 0; }
_container_write_failure() { :; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$LOG" >&2
    failed=$((failed + 1))
  fi
}
# stamp, marker (yes/no), then the optional pin arguments; prints the return code
check() {
  local stamp="$1" marker="$2"
  shift 2
  : >"$LOG"
  rm -f "$HOME/.npm" "$HOME/.npm.pending"
  [[ -n "$stamp" ]] && echo "$stamp" >"$HOME/.npm"
  [[ "$marker" == "yes" ]] && touch "$HOME/.npm.pending"
  local rc=0
  export CHECK_UPDATE_RELEASE=""
  check_for_release github NPM owner/repo "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

expect "current stamp, no marker: nothing to do" 1 "$(check 2.16.0 no)"
expect "current stamp, marker: the update is redone" 0 "$(check 2.16.0 yes)"
expect "the message says why" 1 "$(grep -c 'did not finish' "$LOG")"
expect "old stamp: a normal update" 0 "$(check 2.15.1 no)"
expect "no stamp at all: a normal install" 0 "$(check "" no)"
expect "pinned and current: held back" 1 "$(check 2.16.0 no 2.16.0 "testing")"
expect "pinned, current, marker: redone anyway" 0 "$(check 2.16.0 yes 2.16.0 "testing")"

# The marker carries the version the run started from; the redo reports it
: >"$LOG"
echo 2.16.0 >"$HOME/.npm"
printf '%s' 2.15.1 >"$HOME/.npm.pending"
rc=0
check_for_release github NPM owner/repo >/dev/null 2>&1 || rc=$?
expect "a marker with the old version: redone" 0 "$rc"
expect "the message names the version the run started from" 1 "$(grep -c '2.15.1 -> 2.16.0' "$LOG")"
expect "CS_PREVIOUS_VERSION is the old version on the redo" 2.15.1 "$CS_PREVIOUS_VERSION"
rm -f "$HOME/.npm.pending"
check_for_release github NPM owner/repo >/dev/null 2>&1 || true
expect "without a marker it is the stamp" 2.16.0 "$CS_PREVIOUS_VERSION"
rm -f "$HOME/.npm"
expect "a fresh install has no previous version" "" "$(_forge_previous_version "$HOME/.npm")"

# fetch_and_deploy_release: a redo deploys again, the failed run may have patched the files
eval "$(awk '/^fetch_and_deploy_release[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"
_forge_release_json() { printf '%s' '{"tag_name":"v2.16.0"}' >"$5"; }
_forge_source_url() { echo "https://example.invalid/src.tar.gz"; }
_download_source_tarball() { :; }
_deploy_source_tarball() { echo "deploy" >>"$LOG"; }
deploy() {
  : >"$LOG"
  rm -f "$HOME/.npm.pending"
  echo 2.16.0 >"$HOME/.npm"
  mkdir -p "$TEST_DIR/target"
  [[ "$1" == "yes" ]] && printf '%s' 2.15.1 >"$HOME/.npm.pending"
  fetch_and_deploy_release github NPM owner/repo tarball latest "$TEST_DIR/target" >/dev/null 2>&1
  grep -c '^deploy$' "$LOG"
}
expect "current stamp, no marker: already installed" 0 "$(deploy no)"
expect "current stamp, marker: deployed again" 1 "$(deploy yes)"
rm -f "$HOME/.npm" "$HOME/.npm.pending"

# on_exit: only a run that deployed and exits 0 removes the marker
touch "$HOME/.npm.pending"
(_CS_DEPLOYED=1; on_exit) 2>/dev/null
expect "a clean exit after a deploy removes the marker" no "$([[ -f "$HOME/.npm.pending" ]] && echo yes || echo no)"
touch "$HOME/.npm.pending"
(on_exit) 2>/dev/null
expect "a clean exit without a deploy keeps it" yes "$([[ -f "$HOME/.npm.pending" ]] && echo yes || echo no)"
(_CS_DEPLOYED=1; false; on_exit) 2>/dev/null
expect "a failed run keeps it" yes "$([[ -f "$HOME/.npm.pending" ]] && echo yes || echo no)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
