#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

# Only the lxcfs helper, with its fixed system paths redirected into TEST_DIR.
eval "$(awk '/^_docker_setup_lxcfs_visibility\(\) \{/,/^}/' "$CORE_DIR/lib/runtime.func" |
  sed -e "s#/proc/mounts#$TEST_DIR/mounts#g" \
    -e "s#/etc/docker/daemon.json#$TEST_DIR/daemon.json#g" \
    -e "s#/usr/local/bin/runc-lxcfs#$TEST_DIR/runc-lxcfs#g")"

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
runc() { :; }
echo 'lxcfs /proc/meminfo fuse.lxcfs rw 0 0' >"$TEST_DIR/mounts"

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
# Runs the helper against a fresh daemon.json and prints the resulting default-runtime.
runtime_after() {
  echo "$1" >"$TEST_DIR/daemon.json"
  (
    unset DOCKER_LXCFS_VISIBILITY var_docker_lxcfs
    [[ -n "$2" ]] && export "${2?}"
    _docker_setup_lxcfs_visibility
  )
  jq -r '."default-runtime" // "none"' "$TEST_DIR/daemon.json"
}
plain='{"log-driver": "journald"}'

check "off by default" "none" "$(runtime_after "$plain" "")"
check "DOCKER_LXCFS_VISIBILITY=yes" "lxcfs" "$(runtime_after "$plain" DOCKER_LXCFS_VISIBILITY=yes)"
check "DOCKER_LXCFS_VISIBILITY=TRUE" "lxcfs" "$(runtime_after "$plain" DOCKER_LXCFS_VISIBILITY=TRUE)"
check "var_docker_lxcfs=yes" "lxcfs" "$(runtime_after "$plain" var_docker_lxcfs=yes)"
check "var_docker_lxcfs=no" "none" "$(runtime_after "$plain" var_docker_lxcfs=no)"
check "existing default-runtime kept" "nvidia" \
  "$(runtime_after '{"default-runtime": "nvidia"}' DOCKER_LXCFS_VISIBILITY=yes)"
check "re-run is idempotent" "lxcfs" \
  "$(runtime_after '{"default-runtime": "lxcfs"}' DOCKER_LXCFS_VISIBILITY=yes)"
runtime_after "$plain" DOCKER_LXCFS_VISIBILITY=yes >/dev/null
check "other daemon.json keys kept" "journald" "$(jq -r '."log-driver"' "$TEST_DIR/daemon.json")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
