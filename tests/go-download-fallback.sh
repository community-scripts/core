#!/usr/bin/env bash
# setup_go removed the installed Go before downloading the new one, so a failed
# download (go.dev's redirect answered 404, VE #18893) left the container
# without Go. dl.google.com is now tried directly before giving up.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

# The installed Go is read from /usr/local/bin/go; point it at a stub.
mkdir -p "$TEST_DIR/bin"
printf '#!/bin/sh\necho "go version go1.27.2 linux/amd64"\n' >"$TEST_DIR/bin/go"
chmod +x "$TEST_DIR/bin/go"
eval "$(awk '/^setup_go[(][)] [{]/,/^}/' "$CORE_DIR/lib/runtime.func" | sed "s#/usr/local/bin/go\"#$TEST_DIR/bin/go\"#")"

STD="" ARCH=amd64 CALLS="$TEST_DIR/calls"
msg_info() { :; }
msg_ok() { :; }
msg_error() { echo "error: $*" >>"$CALLS"; }
cache_installed_version() { :; }
ensure_usr_local_bin_persist() { :; }
ensure_dependencies() { :; }
ln() { :; }
tar() { echo "tar" >>"$CALLS"; }
remove_old_tool_version() { echo "remove $1" >>"$CALLS"; }
curl_with_retry() {
  echo "get $1" >>"$CALLS"
  case "$1" in *go.dev/dl/*) ((GODEV_OK)) ;; *dl.google.com/*) ((GOOGLE_OK)) ;; *) return 1 ;; esac
}

: >"$CALLS"
GODEV_OK=0 GOOGLE_OK=1 GO_VERSION=1.27.3 setup_go
expect "falls back to dl.google.com" 0 "$?"
expect "tries go.dev first, then dl.google.com, removes the old Go only after" \
  "get https://go.dev/dl/go1.27.3.linux-amd64.tar.gz|get https://dl.google.com/go/go1.27.3.linux-amd64.tar.gz|remove go|tar" \
  "$(paste -sd'|' "$CALLS")"

: >"$CALLS"
GODEV_OK=0 GOOGLE_OK=0 GO_VERSION=1.27.3 setup_go
expect "both sources down fails with 250" 250 "$?"
expect "and the installed Go is kept" 0 "$(grep -c '^remove' "$CALLS")"

: >"$CALLS"
GODEV_OK=1 GOOGLE_OK=1 GO_VERSION=1.27.3 setup_go
expect "go.dev alone is enough" 1 "$(grep -c '^get' "$CALLS")"

echo "passed=${passed} failed=${failed}"
((failed == 0))
