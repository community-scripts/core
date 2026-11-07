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
# Logs which version each release was asked for; "latest" resolves to 9.9.9.
_forge_release_json() {
  echo "asked $2 $3" >>"$LOG"
  local v="${3#v}"
  [[ "$v" == "latest" ]] && v="9.9.9"
  printf '{"tag_name":"v%s"}' "$v" >"$5"
}
_forge_source_url() { echo "https://example.invalid/$2.tar.gz"; }
_download_source_tarball() { echo "download $1" >>"$LOG"; }
_deploy_source_tarball() { mkdir -p "$2"; }
_forge_asset_urls() { echo "https://example.invalid/liquidsoap_2.4.6-debian-trixie_amd64.deb"; }
curl_download() { echo "download $2" >>"$LOG"; : >"$1"; }
apt() { echo "apt $*" >>"$LOG"; }
dpkg() { [[ "$1" == "--print-architecture" ]] && echo amd64; }

# One finished run: the pending markers go when it exits 0.
deploy() {
  : >"$LOG"
  fetch_and_deploy_release "$@" >/dev/null 2>&1
  rm -f "$HOME"/.*.pending
  grep '^asked ' "$LOG" | cut -d' ' -f3
}

# Subwave pins its own version; liquidsoap keeps its explicit tag, piper stays on latest
export var_appversion=1.29.0
app=subwave
check "the script's own app gets the pin" "1.29.0" "$(deploy github subwave perminder-klair/subwave tarball latest "$TEST_DIR/opt/subwave")"
check "an explicit version of another release is kept" "v2.4.6" "$(deploy github liquidsoap savonet/liquidsoap binary v2.4.6 "" "liquidsoap_*_amd64.deb")"
check "another release on latest stays on latest" "latest" "$(deploy github piper rhasspy/piper tarball latest "$TEST_DIR/opt/piper")"

# The update runs with NSAPP from variables()
unset app
# shellcheck disable=SC2034  # read by fetch_and_deploy_release
NSAPP=subwave
check "NSAPP names the app on an update" "1.29.0" "$(deploy github subwave perminder-klair/subwave tarball latest "$TEST_DIR/opt/subwave2")"
unset NSAPP
check "no known script app: every release is pinned, as before" "1.29.0" "$(deploy github piper rhasspy/piper tarball latest "$TEST_DIR/opt/piper2")"
unset var_appversion

expect_match() { check "$1 / $2: $3" "$3" "$(_forge_is_script_app "$1" "$2" && echo pinned || echo free)"; }
expect_match subwave subwave pinned
expect_match "Paperless" paperless-ngx pinned
expect_match adguardhome adguard pinned
expect_match alertmanager prometheus-alertmanager pinned
expect_match "Meme Search" memesearch pinned
expect_match wkhtmltopdf erpnext free
expect_match jemalloc openproject free
expect_match liquidsoap subwave free
expect_match go go2rtc free

# A .deb never creates /opt/<app>; the stamp alone says it is installed
# shellcheck disable=SC2034  # read by fetch_and_deploy_release
app=subwave
rm -f "$HOME/.liquidsoap"
deploy github liquidsoap savonet/liquidsoap binary v2.4.6 "" "liquidsoap_*_amd64.deb" >/dev/null
check "first .deb run downloads" "1" "$(grep -c '^download ' "$LOG")"
deploy github liquidsoap savonet/liquidsoap binary v2.4.6 "" "liquidsoap_*_amd64.deb" >/dev/null
check "same .deb version again: no download" "0" "$(grep -c '^download ' "$LOG")"
check "and it says so" "1" "$(grep -c 'already installed' "$LOG")"
rm -rf "$TEST_DIR/opt/subwave"
deploy github subwave perminder-klair/subwave tarball latest "$TEST_DIR/opt/subwave" >/dev/null
check "a tarball whose directory is gone is deployed again" "1" "$(grep -c '^download ' "$LOG")"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
