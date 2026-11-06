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

export STD=""
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
runc() { :; }
# Logs calls; Docker counts as running only when docker_active is set.
systemctl() { echo "$*" >>"$TEST_DIR/systemctl.log"; [[ "$1" != is-active ]] || [[ -n "${docker_active:-}" ]]; }
lxcfs_mounts='lxcfs /proc/meminfo fuse.lxcfs rw 0 0'

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
# run <daemon.json> [VAR=value...]: fresh state, run the helper once.
run() {
  echo "$1" >"$TEST_DIR/daemon.json"
  echo "$lxcfs_mounts" >"$TEST_DIR/mounts"
  rm -f "$TEST_DIR/runc-lxcfs"
  shift
  (
    unset DOCKER_LXCFS_VISIBILITY var_docker_lxcfs
    # shellcheck disable=SC2163 # exports each VAR=value argument
    (($#)) && export "$@"
    _docker_setup_lxcfs_visibility
  )
}
field() { jq -r "$1 // \"none\"" "$TEST_DIR/daemon.json"; }
plain='{"log-driver": "journald"}'

run "$plain"
check "off by default" "none" "$(field '."default-runtime"')"
for v in no false 0; do
  run "$plain" DOCKER_LXCFS_VISIBILITY=$v
  check "DOCKER_LXCFS_VISIBILITY=$v stays off" "none" "$(field '."default-runtime"')"
done
run "$plain" DOCKER_LXCFS_VISIBILITY=no var_docker_lxcfs=yes
check "DOCKER_LXCFS_VISIBILITY wins over var_docker_lxcfs" "none" "$(field '."default-runtime"')"
run "$plain" var_docker_lxcfs=yes
check "var_docker_lxcfs=yes enables" "lxcfs" "$(field '."default-runtime"')"

run "$plain" DOCKER_LXCFS_VISIBILITY=TRUE
check "enabled: default-runtime" "lxcfs" "$(field '."default-runtime"')"
check "enabled: runtime registered" "$TEST_DIR/runc-lxcfs" "$(field '.runtimes.lxcfs.path')"
check "enabled: other keys kept" "journald" "$(field '."log-driver"')"
check "enabled: wrapper executable" "yes" "$([[ -x "$TEST_DIR/runc-lxcfs" ]] && echo yes)"
check "enabled: wrapper is valid sh" "yes" "$(sh -n "$TEST_DIR/runc-lxcfs" && echo yes)"
first="$(cat "$TEST_DIR/daemon.json")"
(export DOCKER_LXCFS_VISIBILITY=yes && _docker_setup_lxcfs_visibility)
check "second run leaves daemon.json identical" "$first" "$(cat "$TEST_DIR/daemon.json")"

# Update path: a running dockerd only sees the new default runtime after a reload.
(docker_active=1 && run "$plain" DOCKER_LXCFS_VISIBILITY=yes)
check "running Docker is reloaded" "yes" "$(grep -qx 'reload docker' "$TEST_DIR/systemctl.log" && echo yes)"
rm -f "$TEST_DIR/systemctl.log"
run "$plain" DOCKER_LXCFS_VISIBILITY=yes
check "stopped Docker is not reloaded" "no" "$(grep -q reload "$TEST_DIR/systemctl.log" && echo yes || echo no)"

run '{"default-runtime": "nvidia", "runtimes": {"nvidia": {"path": "nvidia-container-runtime"}}}' DOCKER_LXCFS_VISIBILITY=yes
check "existing default-runtime kept" "nvidia" "$(field '."default-runtime"')"
check "existing default-runtime: no wrapper" "no" "$([[ -e "$TEST_DIR/runc-lxcfs" ]] && echo yes || echo no)"

(lxcfs_mounts='proc /proc proc rw 0 0' && run "$plain" DOCKER_LXCFS_VISIBILITY=yes)
check "no lxcfs mounted: untouched" "none" "$(field '."default-runtime"')"

run '{"log-driver": ' DOCKER_LXCFS_VISIBILITY=yes
check "malformed daemon.json untouched" '{"log-driver": ' "$(cat "$TEST_DIR/daemon.json")"
check "malformed daemon.json: wrapper removed" "no" "$([[ -e "$TEST_DIR/runc-lxcfs" ]] && echo yes || echo no)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
