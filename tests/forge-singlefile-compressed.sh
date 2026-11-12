#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(fetch_and_deploy_release|_forge_workdir|_forge_is_script_app|_forge_descriptor|_forge_strip_v|_forge_previous_version)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
LOG="$TEST_DIR/log"
passed=0 failed=0

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$LOG" >&2
    failed=$((failed + 1))
  fi
}

# shellcheck disable=SC2034  # read by the eval'd helpers
STD=""
jq() { command jq "$@" | tr -d '\r'; }
msg_info() { :; }
msg_ok() { echo "ok: $*" >>"$LOG"; }
msg_warn() { :; }
msg_error() { echo "error: $*" >>"$LOG"; }
ensure_dependencies() { echo "deps $*" >>"$LOG"; }
_forge_release_json() { printf '{"tag_name":"v1.0.0"}' >"$5"; }
_forge_asset_urls() { echo "https://example.invalid/$ASSET"; }
# Serves a fake program, packed the way the asset name says.
curl_download() {
  local out="$1"
  printf '#!/bin/sh\necho program\n' >"$TEST_DIR/plain"
  case "$ASSET" in
  *.tar.gz) tar -czf "$out" -C "$TEST_DIR" plain ;;
  *.gz) gzip -c "$TEST_DIR/plain" >"$out" ;;
  *.bz2) bzip2 -c "$TEST_DIR/plain" >"$out" ;;
  *.xz) xz -c "$TEST_DIR/plain" >"$out" ;;
  *) cp "$TEST_DIR/plain" "$out" ;;
  esac
}

deploy() {
  : >"$LOG"
  rm -rf "$TEST_DIR/opt" "$HOME"/.[!.]*
  fetch_and_deploy_release github "$@" >/dev/null 2>&1
}
runs() { [[ -x "$1" && "$("$1" 2>/dev/null)" == "program" ]] && echo runs || echo "does not run"; }

for pair in gz:gzip bz2:bzip2 xz:xz; do
  ext="${pair%%:*}"
  command -v "${pair##*:}" >/dev/null 2>&1 || continue
  ASSET="app-v1.0.0-linux-amd64.$ext"
  deploy app owner/app singlefile latest "$TEST_DIR/opt/app" "app-v*-linux-amd64.$ext"
  check ".$ext: the program is unpacked and executable" "runs" "$(runs "$TEST_DIR/opt/app/app")"
  check ".$ext: no archive is left in the target" "1" "$(find "$TEST_DIR/opt/app" -type f | wc -l | tr -d ' ')"
done

if command -v bzip2 >/dev/null 2>&1; then
  ASSET="restic_0.18.0_linux_amd64.bz2"
  USE_ORIGINAL_FILENAME=true deploy restic restic/restic singlefile latest "$TEST_DIR/opt/bin" "restic_*_linux_amd64.bz2"
  check "original filename drops the compression suffix" "runs" "$(runs "$TEST_DIR/opt/bin/restic_0.18.0_linux_amd64")"
fi

ASSET="zulip-server-12.4.tar.gz"
USE_ORIGINAL_FILENAME=true deploy zulip zulip/zulip singlefile latest "$TEST_DIR/opt/zulip" "zulip-server-*.tar.gz"
check "a tarball is kept as downloaded" "yes" "$(tar -tzf "$TEST_DIR/opt/zulip/zulip-server-12.4.tar.gz" >/dev/null 2>&1 && echo yes || echo no)"

ASSET="app-linux-amd64"
deploy app owner/app singlefile latest "$TEST_DIR/opt/app" "app-linux-amd64"
check "a plain binary is unchanged" "runs" "$(runs "$TEST_DIR/opt/app/app")"
check "and needs no unpacker" "0" "$(grep -c '^deps' "$LOG")"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
