#!/usr/bin/env bash
# Tools without catch_errors kept core's traps: Ctrl-C stopped only the spinner
# and the run went on, the telemetry EXIT trap replaced the one that stopped the
# spinner, and a failing dpkg (a TrueNAS stub) was read as the architecture.
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

for sig in INT TERM; do
  env --default-signal=INT bash -c "source '$CORE_DIR/core/core.func'; sleep 2; echo continued" >"$TEST_DIR/out" 2>&1 &
  pid=$!
  sleep 0.5
  kill -s "$sig" "$pid"
  wait "$pid"
  rc=$?
  want=130
  [[ "$sig" == TERM ]] && want=143
  expect "SIG$sig ends a tool run" "$want" "$rc"
  expect "and nothing after it runs" 0 "$(grep -c continued "$TEST_DIR/out")"
done

out="$(
  eval "$(awk '/^_telemetry_report_exit[(][)] [{]/,/^}/' "$CORE_DIR/api/telemetry.func")"
  stop_spinner() { echo "spinner stopped"; }
  _tm_dialog_exit() { return 1; }
  post_tool_to_api() { :; }
  post_addon_to_api() { :; }
  msg_info() { :; }
  _telemetry_report_exit 1 "apt install -y smartmontools"
)"
expect "the telemetry exit trap stops the spinner" 1 "$(grep -c 'spinner stopped' <<<"$out")"

mkdir -p "$TEST_DIR/bin"
printf '#!/bin/sh\necho "Package management tools are disabled on TrueNAS appliances."\nexit 1\n' >"$TEST_DIR/bin/dpkg"
chmod +x "$TEST_DIR/bin/dpkg"
arch="$(
  PATH="$TEST_DIR/bin:$PATH"
  eval "$(awk '/^_cs_host_arch[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
  unset INCUS_SERVER_ARCH
  _cs_host_arch
)"
case "$(uname -m)" in x86_64) want=amd64 ;; aarch64) want=arm64 ;; *) want="$(uname -m)" ;; esac
expect "a failing dpkg falls back to uname" "$want" "$arch"

echo "passed=${passed} failed=${failed}"
((failed == 0))
