#!/usr/bin/env bash
# var_github_token is used from the first GitHub call, and a token GitHub
# rejects (401) is dropped instead of failing what works without one.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for fn in _github_token_from_vars _github_token_rejected github_api_call; do
  eval "$(awk "/^${fn}[(][)] [{]/,/^}/" "$CORE_DIR/lib/forge.func")"
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
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
msg_warn() { echo "warn: $*" >>"$TEST_DIR/warn"; }
msg_error() { :; }
msg_ok() { :; }
prompt_for_github_token() { return 1; }
sleep() { :; }

# Answers 401 to a bad token, 200 to the good one and to none at all, and
# records which Authorization header each call carried.
_forge_curl() {
  local out="$1" auth="none" a
  for a in "$@"; do [[ "$a" == Authorization:* ]] && auth="${a#Authorization: Bearer }"; done
  echo "$auth" >>"$TEST_DIR/auth"
  case "$auth" in
  bad) echo 401 ;;
  *) echo '{}' >"$out"; echo 200 ;;
  esac
}

# 1) The token is used on the first call.
unset GITHUB_TOKEN CS_GITHUB_TOKEN_FROM_VARS
var_github_token=good
: >"$TEST_DIR/auth"
github_api_call "https://api.github.com/repos/a/b/releases/latest" "$TEST_DIR/out"
expect "first call succeeds" 0 "$?"
expect "first call carries var_github_token" "good" "$(head -n1 "$TEST_DIR/auth")"
expect "one call only" 1 "$(wc -l <"$TEST_DIR/auth" | tr -d ' ')"

# 2) A rejected token from var_github_token is dropped; the call goes on without it.
unset GITHUB_TOKEN CS_GITHUB_TOKEN_FROM_VARS
var_github_token=bad
: >"$TEST_DIR/auth"
: >"$TEST_DIR/warn"
github_api_call "https://api.github.com/repos/a/b/releases/latest" "$TEST_DIR/out"
expect "rejected token: call still succeeds" 0 "$?"
expect "rejected token: retried without auth" "bad none" "$(paste -sd' ' "$TEST_DIR/auth")"
expect "rejected token: warned once" 1 "$(wc -l <"$TEST_DIR/warn" | tr -d ' ')"
expect "rejected token: unset" "" "${GITHUB_TOKEN:-}"

# 3) A GITHUB_TOKEN the user exported themselves is not dropped silently.
unset CS_GITHUB_TOKEN_FROM_VARS
unset var_github_token
export GITHUB_TOKEN=bad
: >"$TEST_DIR/auth"
github_api_call "https://api.github.com/repos/a/b/releases/latest" "$TEST_DIR/out"
expect "own token: 401 is an error" 22 "$?"
expect "own token: kept" "bad" "${GITHUB_TOKEN:-}"

echo "$passed passed, $failed failed"
((failed == 0))
