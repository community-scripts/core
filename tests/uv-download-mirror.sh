#!/usr/bin/env bash
# On the days GitHub was down every app that needs uv failed in setup_uv, for
# the version lookup or the download. PyPI knows the version and
# releases.astral.sh serves the same release files.
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

eval "$(awk '/^setup_uv[(][)] [{]/,/^}/' "$CORE_DIR/lib/runtime.func" | sed "s#/usr/local/bin/uv\"#$TEST_DIR/none/uv\"#")"

STD="" CALLS="$TEST_DIR/calls"
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { echo "error: $*" >>"$CALLS"; }
ensure_dependencies() { :; }
uname() { echo x86_64; }
# Reaching the unpack step means the download went through.
tar() { return 1; }
get_latest_github_release() { ((API_OK)) && echo 0.13.9; }
curl() { ((PYPI_OK)) && echo '{"info":{"name":"uv","version":"0.13.8"},"releases":{}}'; }
curl_with_retry() {
  echo "get $1" >>"$CALLS"
  case "$1" in *github.com/*) ((GITHUB_OK)) ;; *releases.astral.sh/*) ((MIRROR_OK)) ;; *) return 1 ;; esac
}
run() {
  : >"$CALLS"
  setup_uv
  echo $?
}
F=uv-x86_64-unknown-linux-gnu.tar.gz

API_OK=1 PYPI_OK=1 GITHUB_OK=0 MIRROR_OK=1
expect "the mirror delivers when github.com does not" 251 "$(run)"
expect "github.com first, then releases.astral.sh" \
  "get https://github.com/astral-sh/uv/releases/download/0.13.9/$F|get https://releases.astral.sh/github/uv/releases/download/0.13.9/$F" \
  "$(grep '^get' "$CALLS" | paste -sd'|')"

GITHUB_OK=1
run >/dev/null
expect "github.com alone is enough" 1 "$(grep -c '^get' "$CALLS")"

GITHUB_OK=0 MIRROR_OK=0
expect "both hosts down ends as a download failure" 7 "$(run)"

API_OK=0 MIRROR_OK=1
expect "without the GitHub API the version comes from PyPI" 251 "$(run)"
expect "and that version is downloaded" 1 "$(grep -c "releases.astral.sh/github/uv/releases/download/0.13.8/$F" "$CALLS")"

PYPI_OK=0
expect "no version from either source fails" 7 "$(run)"
expect "naming both" 1 "$(grep -c 'error: Could not fetch latest uv version from GitHub or PyPI' "$CALLS")"
expect "before any download" 0 "$(grep -c '^get' "$CALLS")"

echo "passed=${passed} failed=${failed}"
((failed == 0))
