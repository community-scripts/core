#!/usr/bin/env bash
# The checks, settings and storage dialogs read pveversion, pvesm, pveam and
# pvesh output that core/build.func collects in the background while the engine
# loads. A reader must wait for an unfinished probe, and fall back to the real
# command when a probe failed, never ran or was dropped after a change.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_cs_probe(_run)?[(][)] [{]/,/^}/' "$CORE_DIR/core/build.func")"
eval "$(awk '/^_cs_probe_(read|drop|rc)[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^(_pvesm_status|check_storage_support)[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"

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

# Stands in for the live command, so a fallback is visible.
pvesm() { printf 'Name Type Status Total Used Available %%\nlive dir active 1 1 1 1%%\n'; }

_cs_probe "$CS_PROBE_DIR" pveversion sh -c 'sleep 0.4; echo pve-manager/9.1.4/5ac30304265fbd8e'
_cs_probe "$CS_PROBE_DIR" broken sh -c 'echo partial; exit 2'
_cs_probe "$CS_PROBE_DIR" osfail sh -c 'exit 1'
_cs_probe "$CS_PROBE_DIR" rootdir printf 'Name Type Status Total Used Available %%\nlocal-lvm lvmthin active 1 1 1 1%%\n'
_cs_probe "$CS_PROBE_DIR" vztmpl printf 'Name Type Status Total Used Available %%\n'

expect "a reader waits for a probe still running" "pve-manager/9.1.4/5ac30304265fbd8e" "$(_cs_probe_read pveversion)"
expect "a failed probe gives nothing" "fail" "$(_cs_probe_read broken >/dev/null && echo ok || echo fail)"
expect "a check probe hands over its exit code" "1" "$(_cs_probe_rc osfail)"
expect "a probe never started gives nothing" "fail" "$(_cs_probe_read nextid >/dev/null && echo ok || echo fail)"
expect "pvesm status for a content comes from its probe" "local-lvm" "$(_pvesm_status rootdir | awk 'NR == 2 {print $1}')"
expect "a storage listed by the probe counts" yes "$(check_storage_support rootdir && echo yes || echo no)"
expect "a probe header without storages does not" no "$(check_storage_support vztmpl && echo yes || echo no)"
expect "without a probe for it pvesm runs live" "live" "$(_pvesm_status | awk 'NR == 2 {print $1}')"

_cs_probe_drop rootdir
expect "a dropped probe is asked live" "live" "$(_pvesm_status rootdir | awk 'NR == 2 {print $1}')"

saved="$CS_PROBE_DIR"
CS_PROBE_DIR=""
expect "without a probe dir the caller runs the command" "fail" "$(_cs_probe_read pveversion >/dev/null && echo ok || echo fail)"
CS_PROBE_DIR="$saved"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
