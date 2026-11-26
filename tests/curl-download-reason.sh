#!/usr/bin/env bash
# "Download failed or stalled" three times and then "Download failed: <url>":
# 57 runs a week ended there without a word on whether it was a name, a 404 or
# a stall, because curl's own line never reached the log.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^curl_download[(][)] [{]/,/^}/' "$CORE_DIR/lib/system.func")"

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

msg_warn() { echo "$*" >>"$TEST_DIR/warn"; }
sleep() { :; }
ip() { :; }
curl() {
  echo c >>"$TEST_DIR/calls"
  local n out=""
  n="$(wc -l <"$TEST_DIR/calls" | tr -d ' ')"
  while (($#)); do
    [[ "$1" == "-o" ]] && out="$2"
    shift
  done
  if ((n <= FAILS)); then
    [[ -z "$SAYS" ]] || echo "$SAYS" >&2
    return "$RC"
  fi
  echo data >"$out"
}
run() {
  FAILS="$1" RC="$2" SAYS="$3"
  : >"$TEST_DIR/calls"
  : >"$TEST_DIR/warn"
  rm -f "$TEST_DIR/file"
  curl_download "$TEST_DIR/file" "https://example.org/a.tar.gz"
  rc=$?
}

run 0 0 ""
expect "a download that works says nothing" "0 " "$rc $(cat "$TEST_DIR/warn")"
expect "and the file is in place" data "$(cat "$TEST_DIR/file")"

run 1 6 "curl: (6) Could not resolve host: example.org"
expect "a failed attempt carries curl's reason" "Download failed (attempt 1/3): (6) Could not resolve host: example.org, retrying in 10s..." "$(cat "$TEST_DIR/warn")"
expect "and the next attempt can still succeed" 0 "$rc"

run 9 22 "curl: (22) The requested URL returned error: 404"
expect "three failures end the download" 7 "$rc"
expect "each one is reported" 3 "$(wc -l <"$TEST_DIR/warn" | tr -d ' ')"
expect "the last one too, without a retry" "Download failed (attempt 3/3): (22) The requested URL returned error: 404" "$(tail -n1 "$TEST_DIR/warn")"
expect "no part file is left" 0 "$(ls "$TEST_DIR" | grep -c 'part$')"

run 1 28 "curl: (28) Operation too slow. Less than 1024 bytes/sec transferred the last 60 seconds"
expect "a stall is named as one" 1 "$(grep -c 'Operation too slow' "$TEST_DIR/warn")"

run 1 35 ""
expect "a failure without a line still has its code" "Download failed (attempt 1/3): curl exit 35, retrying in 10s..." "$(cat "$TEST_DIR/warn")"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
