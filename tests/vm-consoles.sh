#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="${CORE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
passed=0 failed=0

msg_warn() { printf '%s\n' "$*" >>"$TEST_DIR/warnings"; }

command() {
  if [[ "${1:-}" == -v ]]; then
    case "${2:-}" in
    grubby | update-grub | grub2-mkconfig | grub-mkconfig)
      [[ "$2" == "$MOCK_BOOT_TOOL" ]]
      return
      ;;
    esac
  fi
  builtin command "$@"
}

mock_update() {
  printf '%s\n' "$@" >>"$TEST_DIR/updates"
  if ((MOCK_UPDATE_RC)); then
    echo "error: simulated bootloader update failure" >&2
    return "$MOCK_UPDATE_RC"
  fi
}

grubby() {
  if [[ "$1" == --info=DEFAULT || "$1" == --info=ALL ]]; then
    if [[ "$1" == --info=ALL ]]; then
      if ((MOCK_ALL_INFO_RC)); then
        echo "error: simulated installed kernel lookup failure" >&2
        return "$MOCK_ALL_INFO_RC"
      fi
      printf '%s\n' "${MOCK_ALL_KERNEL_INFO:-$MOCK_KERNEL_INFO}"
      return 0
    fi
    if ((MOCK_INFO_RC)); then
      echo "error: simulated kernel lookup failure" >&2
      return "$MOCK_INFO_RC"
    fi
    printf '%s\n' "$MOCK_KERNEL_INFO"
  else
    mock_update grubby "$@" || return
    if [[ "$*" == *--args=* ]] && ((MOCK_ADD_RC)); then
      echo "error: simulated console argument addition failure" >&2
      return "$MOCK_ADD_RC"
    fi
  fi
}
update-grub() { mock_update update-grub "$@"; }
grub2-mkconfig() { mock_update grub2-mkconfig "$@"; }
grub-mkconfig() { mock_update grub-mkconfig "$@"; }

virt-customize() {
  local run=""
  while (($#)); do
    if [[ "$1" == --run-command ]]; then
      shift
      run="$1"
    fi
    shift
  done
  [[ "$run" == *"/etc/default/grub"* ]] || return 0
  run="${run//\/etc\/default\/grub/$TEST_DIR/etc/default/grub}"
  run="${run//\/boot\/grub2\/grub.cfg/$TEST_DIR/boot/grub2/grub.cfg}"
  run="${run//\/boot\/grub\/grub.cfg/$TEST_DIR/boot/grub/grub.cfg}"
  printf '%s\n' "$run" >"$TEST_DIR/guest.sh"
  sh -n "$TEST_DIR/guest.sh" || return
  bash "$TEST_DIR/guest.sh"
}

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    printf 'Expected <%s>, got <%s>\n' "$2" "$1" >&2
    exit 1
  fi
}
assert_contains() { grep -qF -- "$2" "$1" || {
  cat "$1" >&2
  exit 1
}; }
assert_success() {
  vm_enable_consoles image.qcow2
  assert_equal "${#_VM_PREPARE_FAILED[@]}" 0
}
assert_failure() {
  vm_enable_consoles image.qcow2
  assert_equal "${#_VM_PREPARE_FAILED[@]}" 1
  [[ "${_VM_PREPARE_FAILED[0]}" == "grub console"* ]] || exit 1
}

fedora_grubby() {
  MOCK_BOOT_TOOL=grubby
  assert_success
  assert_contains "$TEST_DIR/updates" "--update-kernel=ALL"
  assert_contains "$TEST_DIR/updates" "--remove-args=console"
  assert_contains "$TEST_DIR/updates" "--args=console=tty1 console=ttyS0,9600n8"
  assert_equal "$(grep -c '^grubby$' "$TEST_DIR/updates")" 2
  local remove_line add_line
  remove_line="$(grep -n -- '--remove-args=' "$TEST_DIR/updates" | cut -d: -f1)"
  add_line="$(grep -n -- '--args=' "$TEST_DIR/updates" | cut -d: -f1)"
  ((remove_line < add_line)) || exit 1
}
bls_without_grub_defaults() {
  rm "$TEST_DIR/etc/default/grub"
  fedora_grubby
}
grubby_no_serial() {
  MOCK_BOOT_TOOL=grubby
  MOCK_KERNEL_INFO='args="ro root=/dev/vda1 console=tty0 selinux=1 audit=1"'
  assert_success
  assert_contains "$TEST_DIR/updates" "--args=console=tty1 console=ttyS0,115200"
}
grubby_arm_serial() {
  MOCK_BOOT_TOOL=grubby
  MOCK_KERNEL_INFO='args="ro console=tty0 console=ttyAMA0,115200n8 selinux=1 audit=1"'
  assert_success
  assert_contains "$TEST_DIR/updates" "--args=console=tty1 console=ttyAMA0,115200n8"
}
grubby_lookup_failure() {
  MOCK_BOOT_TOOL=grubby
  MOCK_INFO_RC=9
  assert_failure
}
grubby_invalid_info() {
  MOCK_BOOT_TOOL=grubby
  MOCK_KERNEL_INFO='index=0'
  assert_failure
}
grubby_update_failure() {
  MOCK_BOOT_TOOL=grubby
  MOCK_UPDATE_RC=7
  assert_failure
}
grubby_all_lookup_failure() {
  MOCK_BOOT_TOOL=grubby
  MOCK_ALL_INFO_RC=9
  assert_failure
}
grubby_all_invalid_info() {
  MOCK_BOOT_TOOL=grubby
  MOCK_ALL_KERNEL_INFO='index=0'
  assert_failure
}
grubby_add_failure() {
  MOCK_BOOT_TOOL=grubby
  MOCK_ADD_RC=7
  assert_failure
}
grubby_kernel_count_variation() {
  MOCK_BOOT_TOOL=grubby
  MOCK_ALL_KERNEL_INFO=$'args="console=tty0 console=ttyS0,9600n8"\nargs="console=tty0 console=tty1 console=ttyS0,9600n8"'
  assert_success
  assert_contains "$TEST_DIR/updates" "--remove-args=console console console console console"
}
grubby_idempotent() {
  MOCK_BOOT_TOOL=grubby
  MOCK_KERNEL_INFO='args="ro console=tty1 console=ttyS0,9600n8"'
  assert_success
  assert_contains "$TEST_DIR/updates" "--args=console=tty1 console=ttyS0,9600n8"
  ! grep -q 'console=tty1 console=tty1' "$TEST_DIR/updates" || exit 1
}
debian_update_grub() {
  MOCK_BOOT_TOOL=update-grub
  assert_success
  assert_contains "$TEST_DIR/etc/default/grub" 'GRUB_CMDLINE_LINUX="console=tty1 console=ttyS0,9600n8 selinux=1 audit=1"'
  assert_contains "$TEST_DIR/updates" "update-grub"
  assert_success
  assert_equal "$(grep -o 'console=tty1' "$TEST_DIR/etc/default/grub" | wc -l | tr -d ' ')" 1
}
default_cmdline_only() {
  MOCK_BOOT_TOOL=update-grub
  printf '%s\n' 'GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200n8 quiet"' >"$TEST_DIR/etc/default/grub"
  assert_success
  assert_contains "$TEST_DIR/etc/default/grub" 'GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0,115200n8 quiet"'
}
grub2_fallback() {
  MOCK_BOOT_TOOL=grub2-mkconfig
  assert_success
  assert_contains "$TEST_DIR/updates" "$TEST_DIR/boot/grub2/grub.cfg"
}
grub_fallback() {
  MOCK_BOOT_TOOL=grub-mkconfig
  assert_success
  assert_contains "$TEST_DIR/updates" "$TEST_DIR/boot/grub/grub.cfg"
}
legacy_update_failure() {
  MOCK_BOOT_TOOL=update-grub
  MOCK_UPDATE_RC=7
  assert_failure
}
unsupported_grub_tool() { assert_failure; }
invalid_grub_defaults() {
  MOCK_BOOT_TOOL=update-grub
  printf '%s\n' 'GRUB_TIMEOUT=5' >"$TEST_DIR/etc/default/grub"
  assert_failure
}
non_grub_image() {
  rm "$TEST_DIR/etc/default/grub"
  assert_success
  [[ ! -s "$TEST_DIR/updates" ]] || exit 1
}

for backend in pve incus; do
  eval "$(awk '/^_vm_customize\(\)/,/^}/' "$CORE_DIR/$backend/vm-core.func")"
  eval "$(awk '/^vm_enable_consoles\(\)/,/^}/' "$CORE_DIR/$backend/vm-core.func")"
  for test in fedora_grubby bls_without_grub_defaults grubby_no_serial grubby_arm_serial \
    grubby_lookup_failure grubby_invalid_info grubby_update_failure grubby_idempotent \
    grubby_all_lookup_failure grubby_all_invalid_info grubby_add_failure grubby_kernel_count_variation \
    debian_update_grub default_cmdline_only grub2_fallback grub_fallback \
    legacy_update_failure unsupported_grub_tool invalid_grub_defaults non_grub_image; do
    TEST_DIR="$TEST_ROOT/${backend}-${test}"
    mkdir -p "$TEST_DIR/etc/default"
    printf '%s\n' 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' \
      'GRUB_CMDLINE_LINUX="console=ttyS0,9600n8 selinux=1 audit=1"' >"$TEST_DIR/etc/default/grub"
    : >"$TEST_DIR/updates"
    MOCK_BOOT_TOOL="" MOCK_UPDATE_RC=0 MOCK_INFO_RC=0 MOCK_ALL_INFO_RC=0 MOCK_ADD_RC=0 MOCK_ALL_KERNEL_INFO=""
    MOCK_KERNEL_INFO='args="ro root=/dev/vda1 console=ttyS0,9600n8 selinux=1 audit=1"'
    _VM_PREPARE_FAILED=()
    _VM_PREPARE_COLLECTING=1
    export TEST_DIR MOCK_BOOT_TOOL MOCK_UPDATE_RC MOCK_INFO_RC MOCK_KERNEL_INFO MOCK_ALL_INFO_RC MOCK_ADD_RC MOCK_ALL_KERNEL_INFO
    export -f command mock_update grubby update-grub grub2-mkconfig grub-mkconfig
    if ("$test"); then
      printf 'PASS %s/%s\n' "$backend" "$test"
      passed=$((passed + 1))
    else
      printf 'FAIL %s/%s\n' "$backend" "$test" >&2
      failed=$((failed + 1))
    fi
  done
done
printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
