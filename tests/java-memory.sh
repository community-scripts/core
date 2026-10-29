#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

eval "$(awk '/^setup_java_memory\(\) \{/,/^}/' "$CORE_DIR/lib/runtime.func" |
  sed -e "s#/sys/fs/cgroup/memory.max#$TEST_DIR/memory.max#g" \
    -e "s#/proc/mounts#$TEST_DIR/mounts#g" \
    -e "s#/run/systemd/system#$TEST_DIR/systemd#g" \
    -e "s#/etc/systemd/system#$TEST_DIR/units#g")"

msg_ok() { :; }
systemctl() { echo "$*" >>"$TEST_DIR/systemctl.log"; }

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
run() {
  rm -rf "$TEST_DIR/units" "$TEST_DIR/systemd" "$TEST_DIR/memory.max" "$TEST_DIR/systemctl.log"
  [[ "$1" == - ]] || echo "$1" >"$TEST_DIR/memory.max"
  echo "$2" >"$TEST_DIR/mounts"
  [[ "$3" == no ]] || mkdir -p "$TEST_DIR/systemd"
  shift 3
  setup_java_memory "$@"
}
dropin() { echo "$TEST_DIR/units/$1.service.d/java-memory.conf"; }
has_dropin() { [[ -f "$(dropin "$1")" ]] && echo yes || echo no; }
start_pre() {
  local cmd
  printf '%b' "$2" >"$TEST_DIR/meminfo"
  cmd="$(sed -n 's/^ExecStartPre=-+//p' "$(dropin "$1")" |
    sed -e 's/\$\$/$/g' -e "s#%N#$1#g" -e "s#/proc/meminfo#$TEST_DIR/meminfo#g" -e "s#/run/#$TEST_DIR/run/#g")"
  mkdir -p "$TEST_DIR/run"
  eval "$cmd"
}
env_file() { cat "$TEST_DIR/run/$1-java-memory.env" 2>/dev/null || echo none; }

lxcfs='lxcfs /proc/meminfo fuse.lxcfs rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other 0 0'

run max "$lxcfs" yes stirlingpdf unoserver-java
check "pve: drop-in for first unit" "yes" "$(has_dropin stirlingpdf)"
check "pve: drop-in for second unit" "yes" "$(has_dropin unoserver-java)"
check "pve: one daemon-reload" "daemon-reload" "$(cat "$TEST_DIR/systemctl.log")"
check "pve: env file is optional" "EnvironmentFile=-/run/%N-java-memory.env" "$(grep '^EnvironmentFile=' "$(dropin stirlingpdf)")"
check "pve: start step runs as root, failure ignored" "yes" "$(grep -q '^ExecStartPre=-+/bin/sh -c ' "$(dropin stirlingpdf)" && echo yes)"
first="$(cat "$(dropin stirlingpdf)")"
setup_java_memory stirlingpdf
check "second run leaves the drop-in identical" "$first" "$(cat "$(dropin stirlingpdf)")"

start_pre stirlingpdf 'MemTotal:        2097152 kB\nMemFree:         1048576 kB\n'
check "start: MaxRAM from MemTotal" "JAVA_TOOL_OPTIONS=-XX:MaxRAM=2097152k" "$(env_file stirlingpdf)"
start_pre stirlingpdf 'MemTotal:        3145728 kB\n'
check "start: follows a resized CT" "JAVA_TOOL_OPTIONS=-XX:MaxRAM=3145728k" "$(env_file stirlingpdf)"
start_pre stirlingpdf 'MemFree:         1048576 kB\n'
check "start: no MemTotal drops the stale env file" "none" "$(env_file stirlingpdf)"

run 2147483648 "$lxcfs" yes stirlingpdf
check "incus: limit visible, untouched" "no" "$(has_dropin stirlingpdf)"
run - "$lxcfs" yes stirlingpdf
check "no cgroup v2 memory.max: untouched" "no" "$(has_dropin stirlingpdf)"
run max 'proc /proc proc rw 0 0' yes stirlingpdf
check "no lxcfs: untouched" "no" "$(has_dropin stirlingpdf)"
run max "$lxcfs" no stirlingpdf
check "no systemd: untouched" "no" "$(has_dropin stirlingpdf)"
check "no systemd: no daemon-reload" "no" "$([[ -s "$TEST_DIR/systemctl.log" ]] && echo yes || echo no)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
