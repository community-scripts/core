#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^_FORGE_JQ_VKEY_DEF=/,/^_FORGE_JQ_VKEY=/p' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^_forge_(descriptor|curl|designated_release|stable_filter|keep_raw|release_json|explain_failure|require_jq)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR" "${TOOLS_GH_REL_JSON:-}"' EXIT
CALLS="$TEST_DIR/calls"
LOG="$TEST_DIR/log"
OUT="$TEST_DIR/out"
passed=0 failed=0

msg_info() { :; }
msg_ok() { :; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
getent() { return 0; }
sleep() { :; }
_github_release_noapi() { return 1; }
ensure_dependencies() { :; }
curl() {
  local out="" url="" i tag
  local -a args=("$@")
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    https://*) url="${args[$i]}" ;;
    esac
  done
  echo "$url" >>"$CALLS"
  tag="${url##*/}"
  if [[ " $TAGS " == *" $tag "* ]]; then
    printf '{"tag_name":"%s"}' "$tag" >"$out"
    printf '200'
  else
    printf '{"message":"Not Found"}' >"$out"
    printf '404'
  fi
}

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$CALLS" "$LOG" >&2 2>/dev/null
    failed=$((failed + 1))
  fi
}
lookup() {
  : >"$CALLS"
  : >"$LOG"
  : >"$OUT"
  local rc=0
  _forge_release_json github owner/app "$1" "" "$OUT" >/dev/null 2>&1 || rc=$?
  printf '%s %s' "$rc" "$(jq -r '.tag_name // empty' "$OUT" 2>/dev/null | tr -d '\r')"
}

TAGS="v0.35.11"
check "pin without v finds the v tag" "0 v0.35.11" "$(lookup 0.35.11)"
check "and asks twice, not more" "2" "$(wc -l <"$CALLS" | tr -d ' ')"
check "pin with v still direct" "0 v0.35.11" "$(lookup v0.35.11)"
check "a direct hit asks once" "1" "$(wc -l <"$CALLS" | tr -d ' ')"

TAGS="12.4"
check "pin with v finds the plain tag" "0 12.4" "$(lookup v12.4)"

TAGS="v1.0.0"
check "a tag missing both ways fails" "22 " "$(lookup 9.9.9)"
check "without retrying the 404" "2" "$(wc -l <"$CALLS" | tr -d ' ')"
check "and names the HTTP code" "1" "$(grep -c 'HTTP 404' "$LOG")"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
