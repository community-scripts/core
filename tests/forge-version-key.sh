#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# The version key and its callers only; forge.func drags the whole engine along.
eval "$(sed -n '/^_FORGE_JQ_VKEY_DEF=/,/^_FORGE_JQ_VKEY=/p' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^_forge_(highest_version|same_shape|is_current|stable_filter)\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

# Bookworm, Jammy and EL9 containers run jq 1.6, which rejects keywords as
# binding names and lacks the 1.7 builtins. Every program here must parse there.
JQ16_URL="https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64"
JQ16_SHA="af986793a515d500ab2d35f8d2aecd656e764504b789b66d7e1a0b727a124c44"
jq16_binary() {
  if [[ -n "${JQ16:-}" && -x "$JQ16" ]]; then
    printf '%s' "$JQ16"
    return 0
  fi
  [[ "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]] || return 1
  curl -fsSL "$JQ16_URL" -o "$TEST_DIR/jq-1.6" 2>/dev/null || return 1
  [[ "$(sha256sum "$TEST_DIR/jq-1.6" | cut -d' ' -f1)" == "$JQ16_SHA" ]] || return 1
  chmod +x "$TEST_DIR/jq-1.6"
  printf '%s' "$TEST_DIR/jq-1.6"
}

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

highest() { printf '%s\n' "$@" | _forge_highest_version; }
current() { _forge_is_current "$1" "$2" && echo yes || echo no; }

printf '%s' '[{"tag_name":"v5.0.0-rc.1","prerelease":true},{"tag_name":"v4.0.20.3014","prerelease":false},{"tag_name":"v5.0.0","prerelease":false}]' >"$TEST_DIR/releases.json"
# The selection from _forge_release_json, with and without a tag prefix.
pick() {
  local filter
  filter="$(_forge_stable_filter github)"
  if [[ -n "${2:-}" ]]; then
    jq -r --argjson pre "$1" --arg p "$2" "[.[] | ${filter} | select(.tag_name | startswith(\$p))] | sort_by(${_FORGE_JQ_VKEY}) | last // empty | .tag_name" "$TEST_DIR/releases.json"
  else
    jq -r --argjson pre "$1" "[.[] | ${filter}] | sort_by(${_FORGE_JQ_VKEY}) | last // empty | .tag_name" "$TEST_DIR/releases.json"
  fi
}
# get_latest_gitlab_release
latest() { jq -r "sort_by(${_FORGE_JQ_VKEY}) | last | .tag_name // empty" "$TEST_DIR/releases.json"; }

suite() {
  local v
  v="$(jq --version 2>&1)"
  check "$v: newer line beats newer publish" "2.1.0" "$(highest 2.0.5 2.1.0)"
  check "$v: 5.0.0 beats 4.0.20.3014" "5.0.0" "$(highest 4.0.20.3014 5.0.0)"
  check "$v: rc ranks above beta" "1.0.0-rc.1" "$(highest 1.0.0-beta38 1.0.0-rc.1)"
  check "$v: final ranks above rc" "1.0.0" "$(highest 1.0.0-rc.1 1.0.0)"
  check "$v: revision suffixes order by number" "v1.2.3-ls45" "$(highest v1.2.3-ls44 v1.2.3-ls45)"
  check "$v: 4.0.20.3014 is behind 5.0.0" "no" "$(current 4.0.20.3014 5.0.0)"
  check "$v: 5.0.0 is current" "yes" "$(current 5.0.0 4.0.20.3014)"
  check "$v: stable selection" "v5.0.0" "$(pick false)"
  check "$v: pre-release selection still prefers the final" "v5.0.0" "$(pick true)"
  check "$v: prefixed selection" "v5.0.0" "$(pick false v5)"
  check "$v: gitlab latest" "v5.0.0" "$(latest)"
}

suite
if jq16="$(jq16_binary)"; then
  jq() { "$jq16" "$@"; }
  suite
  unset -f jq
elif [[ "${CI:-}" == "true" ]]; then
  echo "FAIL jq 1.6 could not be fetched for the compatibility run" >&2
  failed=$((failed + 1))
else
  echo "SKIP jq 1.6 (set JQ16=/path/to/jq-1.6 to run it)"
fi

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
