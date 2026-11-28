#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^get_header[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"

TEST_DIR="$(mktemp -d)"
trap 'chmod -R u+w "$TEST_DIR" 2>/dev/null; rm -rf -- "$TEST_DIR"' EXIT
STATE="$TEST_DIR/state"
CURL_LOG="$TEST_DIR/curl.log"
BANNER='  __ _____   ____  ____
 / // / _ | / __ \/ __/'
passed=0 failed=0
unset COMMUNITY_SCRIPTS_CORE_DIR

community_scripts_dir() { echo "$STATE"; }
# Serves the one banner that exists; writing it fails like curl does (23).
curl() {
  local out="" url=""
  while (($#)); do
    case "$1" in
    -o) out="$2" && shift 2 ;;
    --connect-timeout | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1" && shift ;;
    esac
  done
  echo "$url" >>"$CURL_LOG"
  [[ "$url" == */headers/vm/homeassistantos ]] || return 22
  if [[ -n "$out" ]]; then
    printf '%s\n' "$BANNER" 2>/dev/null >"$out" || return 23
  else
    printf '%s\n' "$BANNER"
  fi
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
reset() {
  chmod -R u+w "$TEST_DIR" 2>/dev/null
  rm -rf "$STATE" "$CURL_LOG"
  : >"$CURL_LOG"
}

export APP="Home Assistant OS"
export APP_TYPE=vm

reset
expect "a writable cache: the banner" "$BANNER" "$(get_header)"
expect "and it is cached" "$BANNER" "$(cat "$STATE/headers/vm/homeassistantos" 2>/dev/null)"
: >"$CURL_LOG"
expect "the next run reads the cache" "$BANNER" "$(get_header)"
expect "without a download" 0 "$(wc -l <"$CURL_LOG" | tr -d ' ')"

# A root run left the cache behind, a non-root run cannot write to it
reset
mkdir -p "$STATE/headers/vm"
chmod 555 "$STATE/headers/vm"
if [[ -w "$STATE/headers/vm" ]]; then
  echo "SKIP an unwritable cache: running as root, which writes anywhere"
else
  expect "an unwritable cache: the banner still shows" "$BANNER" "$(get_header)"
  expect "nothing is cached" no "$([[ -e "$STATE/headers/vm/homeassistantos" ]] && echo yes || echo no)"
fi

reset
export APP="No Such App"
rc=0
get_header >/dev/null || rc=$?
expect "an app without a banner returns 1" 1 "$rc"
expect "and leaves no empty file behind" 0 "$(find "$STATE" -type f 2>/dev/null | wc -l | tr -d ' ')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
