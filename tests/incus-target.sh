#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^incus_target[(][)] [{]/,/^}/' "$CORE_DIR/incus/core.func")"
eval "$(awk '/^_cs_host_arch[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^kvm_check[(][)] [{]/,/^}/' "$CORE_DIR/incus/vm-core.func")"
eval "$(awk '/^vm_resolve_storage[(][)] [{]/,/^}/' "$CORE_DIR/incus/vm-core.func")"
eval "$(awk '/^incus_get_storage_pools[(][)] [{]/,/^}/' "$CORE_DIR/incus/core.func")"
eval "$(awk '/^incus_default_storage_pool[(][)] [{]/,/^}/' "$CORE_DIR/incus/core.func")"
eval "$(awk '/^incus_target_is_local[(][)] [{]/,/^}/' "$CORE_DIR/incus/core.func")"
eval "$(awk '/^_incus_target_gpus[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"
eval "$(awk '/^_vm_pool_free_gib[(][)] [{]/,/^}/' "$CORE_DIR/incus/vm-core.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/log"
passed=0 failed=0

incus_msg_custom() { echo "$3" >>"$LOG"; }
# The client answers for its default remote; `incus info` is the server's YAML.
incus() {
  case "$1 ${2:-}" in
  "remote get-default") echo "${MOCK_REMOTE:-local}" ;;
  "profile device") [[ -n "${MOCK_ROOT_POOL:-}" ]] && echo "$MOCK_ROOT_POOL" ;;
  "storage list") printf '%s\n' ${MOCK_POOLS:-} ;;
  "storage info") ;;
  "storage get") echo "$TEST_DIR" ;;
  "info --resources")
    printf 'CPU:\n  Vendor: GenuineIntel\nGPUs:\n  Card 0:\n    Vendor: Intel Corporation (8086)\n    PCI address: 0000:00:02.0\n  Card 1:\n    Vendor: NVIDIA Corporation (10de)\n    PCI address: 0000:01:00.0\nNICs:\n  Card 0:\n    Vendor: Intel Corporation (8086)\n    PCI address: 0000:03:00.0\n'
    ;;
  "info ")
    # Newer servers indent the list by four; kernel_architecture is the scalar we prefer.
    if [[ -n "${MOCK_KERNEL_ARCH:-}" ]]; then
      printf 'config: {}\nenvironment:\n  addresses: []\n  architectures:\n    - %s\n    - i686\n  kernel_architecture: %s\n  kernel_version: 6.12.0-incusos\n  server_name: box\n' "${MOCK_ARCH:-x86_64}" "$MOCK_KERNEL_ARCH"
    else
      printf 'config: {}\nenvironment:\n  addresses: []\n  architectures:\n    - %s\n    - i686\n  kernel_version: 6.12.0-incusos\n  server_name: box\n' "${MOCK_ARCH:-x86_64}"
    fi
    if [[ -n "${MOCK_DRIVER:-}" ]]; then printf '  driver: %s\n' "$MOCK_DRIVER"; fi
    ;;
  esac
}

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

: >"$LOG"
MOCK_REMOTE=incusos MOCK_ARCH=aarch64 incus_target
expect "the default remote is the target" incusos "$INCUS_REMOTE"
expect "the server architecture is read, in Debian naming" arm64 "$INCUS_SERVER_ARCH"
expect "the server kernel is read" 6.12.0-incusos "$INCUS_SERVER_KERNEL"
expect "incus_target itself prints nothing" "" "$(cat "$LOG")"

: >"$LOG"
MOCK_REMOTE=local MOCK_ARCH=x86_64 incus_target
expect "local stays local" local "$INCUS_REMOTE"
expect "x86_64 becomes amd64" amd64 "$INCUS_SERVER_ARCH"
expect "_cs_host_arch follows the server" arm64 "$(INCUS_SERVER_ARCH=aarch64 _cs_host_arch)"
expect "_cs_host_arch maps this machine without dpkg" amd64 "$(INCUS_SERVER_ARCH="" _cs_host_arch)"

MOCK_REMOTE=lab MOCK_ARCH=riscv64 incus_target
expect "an unmapped architecture is passed through" riscv64 "$INCUS_SERVER_ARCH"

MOCK_REMOTE=incus-001 MOCK_ARCH=i686 MOCK_KERNEL_ARCH=x86_64 incus_target
expect "kernel_architecture wins over the list" amd64 "$INCUS_SERVER_ARCH"

fatal() { echo "fatal: $*"; }
expect "a remote with qemu passes without a local /dev/kvm" "" "$(INCUS_REMOTE=incus001 MOCK_DRIVER="lxc | qemu" kvm_check)"
expect "a remote without qemu stops" 1 "$(INCUS_REMOTE=incus001 MOCK_DRIVER=lxc kvm_check | grep -c "no qemu driver")"
expect "a remote without driver info is not judged by local /dev/kvm" "" "$(INCUS_REMOTE=incus001 kvm_check)"

unset var_storage VM_STORAGE
MOCK_ROOT_POOL=local MOCK_POOLS="data local" vm_resolve_storage
expect "the default profile's root pool is used" local "$var_storage"
unset var_storage
MOCK_POOLS="nvme local" vm_resolve_storage
expect "without a root pool the first pool is used" nvme "$var_storage"
var_storage=data
MOCK_ROOT_POOL=local vm_resolve_storage
expect "a pinned var_storage is kept" data "$var_storage"
unset var_storage
VM_STORAGE=fast MOCK_ROOT_POOL=local vm_resolve_storage
expect "VM_STORAGE wins" fast "$var_storage"

expect "GPUs come from the target, NICs are skipped" "8086 0000:00:02.0,10de 0000:01:00.0" "$(_incus_target_gpus | paste -sd,)"
expect "local is local" 0 "$(INCUS_REMOTE=local incus_target_is_local; echo $?)"
expect "a remote is not local" 1 "$(INCUS_REMOTE=incus001 incus_target_is_local; echo $?)"
expect "pool space falls back to df locally" 1 "$(INCUS_REMOTE=local _vm_pool_free_gib default >/dev/null; echo $? | grep -c 0)"
expect "pool space never uses the local df on a remote" "" "$(INCUS_REMOTE=incus001 _vm_pool_free_gib default)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
