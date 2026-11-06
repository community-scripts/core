#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_github_release_noapi[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
OUT="$TEST_DIR/out"
passed=0 failed=0

# github.com as seen for a repo moved from old-owner/Tool to new-owner/Tool.
curl() {
  local url="${*: -1}"
  case "$url" in
  */releases/latest)
    printf 'HTTP/2 301\r\nlocation: https://github.com/new-owner/Tool/releases/latest\r\n\r\n'
    [[ " $* " == *" -sSIL "* ]] &&
      printf 'HTTP/2 302\r\nlocation: https://github.com/new-owner/Tool/releases/tag/v2.0.0\r\n\r\n'
    ;;
  */releases/expanded_assets/*)
    printf '%s\n' '<ul>' \
      '<li><a href="/new-owner/Tool/releases/download/v2.0.0/tool_2.0.0_amd64.deb">deb</a></li>' \
      '<li><a href="/new-owner/Tool/releases/download/v2.0.0/tool_2.0.0_arm64.deb">deb</a></li>' \
      '<li><a href="/new-owner/Tool/archive/refs/tags/v2.0.0.tar.gz">Source</a></li>' \
      '<li><a href="/new-owner/Tool/releases/tag/v2.0.0">tag</a></li>' \
      '</ul>'
    ;;
  *) return 22 ;;
  esac
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

_github_release_noapi old-owner/Tool v2.0.0 "$OUT"
expect "a named tag of a moved repo resolves" 0 "$?"
expect "its assets are found under the new owner" 2 "$(jq '.assets | length' "$OUT")"
expect "the deb for amd64 is among them" tool_2.0.0_amd64.deb "$(jq -r '.assets[0].name' "$OUT")"
expect "the download URL keeps the new owner" \
  https://github.com/new-owner/Tool/releases/download/v2.0.0/tool_2.0.0_amd64.deb "$(jq -r '.assets[0].browser_download_url' "$OUT")"

_github_release_noapi old-owner/Tool latest "$OUT"
expect "latest of a moved repo follows the redirect" 0 "$?"
expect "latest resolves to the tag" v2.0.0 "$(jq -r '.tag_name' "$OUT")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
