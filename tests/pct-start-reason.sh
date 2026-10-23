#!/usr/bin/env bash
# _pct_start_failed runs under the host's errexit and ERR trap. Its journal
# filter ends in grep -v, which exits 1 when nothing survives, so the helper
# that explains a failed start was itself reported as the failure.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_pct_start_failed[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export TAB="  " YW="" CL=""
BUILD_LOG="$TEST_DIR/build.log"
JOURNAL="$TEST_DIR/journal"
: >"$JOURNAL"
passed=0 failed=0

journalctl() { cat "$JOURNAL"; }
msg_custom() { :; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# The helper as the host runs it: errexit, errtrace, pipefail and an ERR trap.
run_helper() {
  (
    set -Eeo pipefail
    trap 'echo TRAPPED; exit 99' ERR
    _pct_start_failed 100 "$1"
    echo "rc=$?"
  ) 2>&1
}

out="$(run_helper "startup for container '100' failed")"
expect "an empty journal does not trip the ERR trap" 0 "$(grep -c TRAPPED <<<"$out")"
expect "the helper returns 0" 1 "$(grep -c '^rc=0$' <<<"$out")"
expect "the pct output is shown instead" 1 "$(grep -c "startup for container" <<<"$out")"
expect "the build log gets the pct output" 1 "$(grep -c "startup for container" "$BUILD_LOG")"

: >"$BUILD_LOG"
printf '%s\n' 'Starting pve-container@100.service - PVE LXC Container: 100...' \
  'lxc-start: 100: conf.c: mount_entry: No such file or directory' \
  'pve-container@100.service: Control process exited, code=exited, status=1/FAILURE' \
  'Failed to start pve-container@100.service - PVE LXC Container: 100.' >"$JOURNAL"
out="$(run_helper "pct out")"
expect "the journal reason survives the filter" 1 "$(grep -c 'conf.c: mount_entry' <<<"$out")"
expect "systemd bookkeeping is dropped" 0 "$(grep -c 'Control process exited' <<<"$out")"
expect "a journal with lines does not trip the trap either" 0 "$(grep -c TRAPPED <<<"$out")"
expect "the reason lands in the build log" 1 "$(grep -c 'conf.c: mount_entry' "$BUILD_LOG")"

echo "$passed passed, $failed failed"
((failed == 0))
