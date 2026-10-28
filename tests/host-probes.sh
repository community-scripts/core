#!/usr/bin/env bash
# The host checks read pveversion, pvesm and pvesh output that core/build.func
# collects in the background while the engine loads. A reader must wait for an
# unfinished probe, and fall back to the real command when a probe failed or
# never ran.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_cs_probe[(][)] [{]/,/^}/' "$CORE_DIR/core/build.func")"
eval "$(awk '/^_cs_probe_read[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^_probe_has_storage[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"

CS_PROBE_DIR="$(mktemp -d)"
trap 'rm -rf -- "$CS_PROBE_DIR"' EXIT
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

_cs_probe "$CS_PROBE_DIR" pveversion sh -c 'sleep 0.4; echo pve-manager/9.1.4/5ac30304265fbd8e'
_cs_probe "$CS_PROBE_DIR" broken sh -c 'echo partial; exit 2'
_cs_probe "$CS_PROBE_DIR" rootdir printf 'Name Type Status Total Used Available %%\nlocal-lvm lvmthin active 1 1 1 1%%\n'
_cs_probe "$CS_PROBE_DIR" vztmpl printf 'Name Type Status Total Used Available %%\n'

expect "a reader waits for a probe still running" "pve-manager/9.1.4/5ac30304265fbd8e" "$(_cs_probe_read pveversion)"
expect "a failed probe gives nothing" "fail" "$(_cs_probe_read broken >/dev/null && echo ok || echo fail)"
expect "a probe never started gives nothing" "fail" "$(_cs_probe_read nextid >/dev/null && echo ok || echo fail)"
expect "a storage listed by the probe counts" yes "$(_probe_has_storage rootdir && echo yes || echo no)"
expect "a header without storages does not" no "$(_probe_has_storage vztmpl && echo yes || echo no)"

saved="$CS_PROBE_DIR"
CS_PROBE_DIR=""
expect "without a probe dir the caller runs the command" "fail" "$(_cs_probe_read pveversion >/dev/null && echo ok || echo fail)"
CS_PROBE_DIR="$saved"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
