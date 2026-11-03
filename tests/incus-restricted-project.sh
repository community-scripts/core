#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_incus_launch_refusal[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"

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

# Verbatim from the telemetry record of 2026-11-02, a host whose default
# project carries restricted=true.
MKNOD='Launching debian-2
Error: Failed instance creation: Failed checking if instance creation allowed: Invalid value "true" for config "security.syscalls.intercept.mknod" on container "debian-2" of project "default": Container syscall interception is forbidden'

expect "the refused key and project are named" \
  "security.syscalls.intercept.mknod|default" "$(_incus_launch_refusal "$MKNOD")"

NESTING='Error: Failed instance creation: Failed checking if instance creation allowed: Invalid value "true" for config "security.nesting" on container "ct-1" of project "lab": Container nesting is forbidden'
expect "nesting is caught in a non-default project" \
  "security.nesting|lab" "$(_incus_launch_refusal "$NESTING")"

# The retry loop appends each attempt, so the helper reads the newest one.
expect "the last attempt wins" \
  "security.nesting|lab" "$(_incus_launch_refusal "$MKNOD
$NESTING")"

# Without the project clause the key still has to come through.
NOPROJ='Error: Invalid value "true" for config "security.nesting": Container nesting is forbidden'
expect "a missing project clause falls back" \
  "security.nesting|default" "$(_incus_launch_refusal "$NOPROJ")"

# An image problem must still reach the retry loop.
PULL='Error: Failed instance creation: Failed getting image: not found'
expect "an image failure is not a refusal" "" "$(_incus_launch_refusal "$PULL")"
expect "  and it reports no refusal" 1 "$(_incus_launch_refusal "$PULL" >/dev/null 2>&1; echo $?)"

# "is forbidden" alone is not enough; a config key has to be named.
expect "a forbidden message without a key is not a refusal" 1 \
  "$(_incus_launch_refusal 'Error: Container nesting is forbidden' >/dev/null 2>&1; echo $?)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
