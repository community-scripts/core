#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^_FORGE_JQ_VKEY_DEF=/,/^_FORGE_JQ_VKEY=/p' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^_forge_(descriptor|curl|designated_release|stable_filter|keep_raw|release_json|explain_failure)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR" "${TOOLS_GH_REL_JSON:-}"' EXIT
CALLS="$TEST_DIR/calls"
LOG="$TEST_DIR/log"
OUT="$TEST_DIR/out"
passed=0 failed=0

msg_info() { echo "info: $*" >>"$LOG"; }
msg_ok() { echo "ok: $*" >>"$LOG"; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
getent() { return 0; }
_github_release_noapi() { return 1; }
ensure_dependencies() {
  echo "ensure_dependencies $*" >>"$CALLS"
  return "${MOCK_DEPS_RC:-0}"
}
# /releases/latest answers per MOCK_LATEST_*, every other URL per MOCK_*.
curl() {
  local out="" url="" i
  local -a args=("$@")
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    https://*) url="${args[$i]}" ;;
    esac
  done
  echo "curl $url" >>"$CALLS"
  if [[ "$url" == */releases/latest ]]; then
    printf '%s' "${MOCK_LATEST_BODY:-null}" >"$out"
    printf '%s' "${MOCK_LATEST_CODE:-404}"
    return 0
  fi
  printf '%s' "${MOCK_BODY:-}" >"$out"
  printf '%s' "${MOCK_CODE:-200}"
  return "${MOCK_RC:-0}"
}

run() {
  : >"$CALLS"
  : >"$LOG"
  : >"$OUT"
  _forge_release_json github filebrowser/filebrowser latest "" "$OUT"
}
line_of() { grep -nF -- "$1" "$CALLS" | head -n1 | cut -d: -f1; }
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

MOCK_CODE=200 MOCK_BODY='<html><body>Blocked by proxy</body></html>' run
expect "an HTML page is reported as not JSON" 22 "$?"
expect "the message names the body" 1 "$(grep -c 'The response starts with: <html><body>Blocked by proxy</body></html>' "$LOG")"
expect "jq is ensured before the first request" yes "$( (($(line_of ensure_dependencies) < $(line_of curl))) && echo yes || echo no)"

MOCK_CODE=200 MOCK_BODY='' run
expect "an empty body is reported as not JSON" 22 "$?"
expect "the message says the body was empty" 1 "$(grep -c 'The response starts with: (empty)' "$LOG")"

MOCK_DEPS_RC=1 run
expect "a missing jq stops the lookup" 100 "$?"
expect "nothing is fetched without jq" 0 "$(grep -c curl "$CALLS")"

# VM scripts load forge.func without system.func.
(
  unset -f ensure_dependencies
  MOCK_BODY='[{"tag_name":"v1.0.0","draft":false,"prerelease":false}]' run
)
expect "without system.func the lookup uses the jq that is there" 0 "$?"
expect "without system.func the release resolves" v1.0.0 "$(jq -r .tag_name "$OUT")"

(
  unset -f ensure_dependencies
  PATH="$TEST_DIR/no-bin"
  run
)
expect "without system.func a missing jq stops the lookup" 100 "$?"
expect "without system.func nothing is fetched without jq" 0 "$(grep -c curl "$CALLS")"

MOCK_BODY='[{"tag_name":"v1.0.0","draft":false,"prerelease":false},{"tag_name":"v2.0.0-rc.1","draft":false,"prerelease":true}]' run
expect "the release list still resolves" 0 "$?"
expect "the stable release wins" v1.0.0 "$(jq -r .tag_name "$OUT")"

MOCK_LATEST_CODE=200 MOCK_LATEST_BODY='{"tag_name":"v3.0.0","draft":false,"prerelease":false}' run
expect "the designated release still resolves" 0 "$?"
expect "the designated release is used" v3.0.0 "$(jq -r .tag_name "$OUT")"
expect "only one request was needed" 1 "$(grep -c curl "$CALLS")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
