#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(fetch_and_deploy_release|_forge_deb_units|_forge_workdir|_forge_is_script_app|_forge_descriptor|_forge_strip_v|_forge_previous_version)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

if [[ ! -d /run/systemd/system ]]; then
  echo "SKIP: no /run/systemd/system on this machine"
  exit 0
fi

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
msg_ok() { :; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
_forge_release_json() { printf '{"tag_name":"v2.0.0"}' >"$5"; }
_forge_asset_urls() { echo "https://example.invalid/demo_2.0.0_amd64.deb"; }
curl_download() { : >"$1"; }
apt() { echo "apt $*" >>"$LOG"; }
dpkg-deb() { echo demo; }
dpkg() {
  case "$1" in
  --print-architecture) echo amd64 ;;
  -s) [[ "$INSTALLED" == yes ]] ;;
  -L) printf '%s\n' /usr/bin/demo /lib/systemd/system/demo.service \
    /lib/systemd/system/demo-worker.service /lib/systemd/system/demo-job@.service ;;
  esac
}
systemctl() {
  case "$1" in
  is-active) [[ " $ACTIVE " == *" $3 "* ]] ;;
  is-enabled) [[ " $ENABLED " == *" $3 "* ]] ;;
  restart | start) echo "$1 $2" >>"$LOG" ;;
  esac
}

deploy() {
  : >"$LOG"
  rm -f "$HOME"/.demo*
  fetch_and_deploy_release github demo owner/demo binary latest "" "demo_*_amd64.deb" >/dev/null 2>&1
  grep -E '^(start|restart) ' "$LOG" | sort | tr '\n' ' ' | sed 's/ $//'
}

INSTALLED=no ACTIVE="" ENABLED="demo.service"
check "fresh install starts the enabled unit only" "start demo.service" "$(deploy)"

INSTALLED=yes ACTIVE="demo.service demo-worker.service" ENABLED="demo.service demo-worker.service"
check "upgrade restarts the units that ran" "restart demo-worker.service restart demo.service" "$(deploy)"

INSTALLED=yes ACTIVE="" ENABLED="demo.service"
check "a unit stopped before the update stays stopped" "" "$(deploy)"

INSTALLED=yes ACTIVE="demo.service" ENABLED="demo.service"
check "templates are never touched" "0" "$(deploy >/dev/null; grep -c 'demo-job@' "$LOG")"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
