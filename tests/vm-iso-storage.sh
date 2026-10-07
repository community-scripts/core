#!/usr/bin/env bash
set -euo pipefail

COMMUNITY_SCRIPTS_CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export COMMUNITY_SCRIPTS_CORE_DIR
pveversion() { :; }
# shellcheck disable=SC1091
source "${COMMUNITY_SCRIPTS_CORE_DIR}/pve/vm-core.func"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
PVE_CALLS="$TEST_DIR/pvesm.log"
ERRORS="$TEST_DIR/errors.log"
MOCK_STATUS=$'Name Type Status Total Used Available %\niso-store nfs active 1000 100 900 10'
CL="" BL="" GN=""
STORAGE="local-lvm"
STORAGE_TYPE="lvmthin"
DISK_IMPORT_FORMAT="raw"
THIN="discard=on,ssd=1,"
passed=0 failed=0

msg_ok() { :; }
msg_error() { printf '%s\n' "$*" >>"$ERRORS"; }
vm_dialog() {
  VM_DIALOG_RESULT="${MOCK_CHOICE:-}"
  return "${MOCK_DIALOG_RC:-0}"
}
exit_script() { exit 0; }
tput() { echo 80; }
pvesm() {
  printf '%s\n' "$*" >>"$PVE_CALLS"
  case "$1" in
  status)
    [[ "$*" == "status -content iso -enabled 1" ]] || return 2
    [[ "${MOCK_STATUS_RC:-0}" == 0 ]] || return "$MOCK_STATUS_RC"
    printf '%s\n' "$MOCK_STATUS"
    ;;
  path)
    [[ "${MOCK_PATH_RC:-0}" == 0 ]] || return "$MOCK_PATH_RC"
    printf '%s\n' "${MOCK_PATH-/mnt/custom iso directory/template/iso/${2##*/}}"
    ;;
  *) return 2 ;;
  esac
}

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    printf 'Expected <%s>, got <%s>\n' "$2" "$1" >&2
    exit 1
  fi
}

expect_failure() {
  local filename="$1" message="$2" rc=0
  vm_select_iso_storage "$filename" "arch-linux" || rc=$?
  assert_equal "$rc" 119
  grep -qF "$message" "$ERRORS" || {
    cat "$ERRORS" >&2
    exit 1
  }
}

single_storage() {
  vm_select_iso_storage "archlinux-x86_64.iso" "arch-linux" || exit 1
  assert_equal "$ISO_STORAGE" "iso-store"
  assert_equal "$ISO_VOLUME" "iso-store:iso/archlinux-x86_64.iso"
  assert_equal "$ISO_PATH" "/mnt/custom iso directory/template/iso/archlinux-x86_64.iso"
  assert_equal "$STORAGE" "local-lvm"
  assert_equal "$STORAGE_TYPE" "lvmthin"
  assert_equal "$DISK_IMPORT_FORMAT" "raw"
  assert_equal "$THIN" "discard=on,ssd=1,"
  grep -qxF "path $ISO_VOLUME" "$PVE_CALLS" || exit 1
}

local_storage() {
  MOCK_STATUS=$'Name Type Status Total Used Available %\nlocal dir active 1000 100 900 10'
  MOCK_PATH="/var/lib/vz/template/iso/archlinux-x86_64.iso"
  vm_select_iso_storage "archlinux-x86_64.iso" || exit 1
  assert_equal "$ISO_VOLUME" "local:iso/archlinux-x86_64.iso"
  assert_equal "$ISO_PATH" "$MOCK_PATH"
}

multiple_storage() {
  MOCK_STATUS+=$'\nsecond-store dir active 1000 100 900 10'
  MOCK_CHOICE="second-store"
  vm_select_iso_storage "archlinux-x86_64.iso" || exit 1
  assert_equal "$ISO_STORAGE" "second-store"
}

explicit_storage() {
  MOCK_STATUS+=$'\nsecond-store cifs active 1000 100 900 10'
  VM_ISO_STORAGE="second-store"
  ISO_STORAGE="iso-store"
  VM_UNATTENDED=1
  MOCK_DIALOG_RC=2
  vm_select_iso_storage "archlinux-x86_64.iso" || exit 1
  assert_equal "$ISO_VOLUME" "second-store:iso/archlinux-x86_64.iso"
}

preselected_storage() {
  ISO_STORAGE="iso-store"
  MOCK_DIALOG_RC=2
  single_storage
}

unattended_single() {
  VM_UNATTENDED=1
  single_storage
}
unattended_multiple() {
  MOCK_STATUS+=$'\nsecond-store dir active 1000 100 900 10'
  VM_UNATTENDED=1
  expect_failure "archlinux-x86_64.iso" "set VM_ISO_STORAGE"
}

inactive_storage() {
  MOCK_STATUS+=$'\nunavailable dir inactive 1000 100 900 10'
  MOCK_DIALOG_RC=2
  single_storage
}

no_storage() {
  MOCK_STATUS=$'Name Type Status Total Used Available %\nunavailable dir inactive 0 0 0 0'
  expect_failure "archlinux-x86_64.iso" "No active, enabled storage"
  ! grep -q '^path ' "$PVE_CALLS" || exit 1
}

invalid_preset() {
  VM_ISO_STORAGE="local"
  expect_failure "archlinux-x86_64.iso" "ISO storage 'local' is not active"
}

inactive_preset() {
  MOCK_STATUS+=$'\nunavailable dir inactive 0 0 0 0'
  VM_ISO_STORAGE="unavailable"
  expect_failure "archlinux-x86_64.iso" "ISO storage 'unavailable' is not active"
}

status_error() {
  MOCK_STATUS_RC=1
  expect_failure "archlinux-x86_64.iso" "Unable to query"
}
path_error() {
  MOCK_PATH_RC=1
  expect_failure "archlinux-x86_64.iso" "Unable to resolve"
}
relative_path() {
  MOCK_PATH="template/iso/archlinux-x86_64.iso"
  expect_failure "archlinux-x86_64.iso" "Invalid path"
}
empty_path() {
  MOCK_PATH=""
  expect_failure "archlinux-x86_64.iso" "Invalid path"
}
multiline_path() {
  MOCK_PATH=$'/mnt/iso/archlinux-x86_64.iso\nunexpected'
  expect_failure "archlinux-x86_64.iso" "Invalid path"
}
invalid_filename() { expect_failure "../archlinux-x86_64.iso" "Invalid ISO filename"; }
missing_filename() { expect_failure "" "Invalid ISO filename"; }
invalid_selection() {
  MOCK_STATUS+=$'\nsecond-store dir active 1000 100 900 10'
  MOCK_CHOICE="local"
  expect_failure "archlinux-x86_64.iso" "ISO storage 'local' is not active"
}

cancellation() {
  MOCK_STATUS+=$'\nsecond-store dir active 1000 100 900 10'
  MOCK_DIALOG_RC=1
  (
    vm_select_iso_storage "archlinux-x86_64.iso"
    exit 77
  ) || exit 1
  ! grep -q '^path ' "$PVE_CALLS" || exit 1
}

incus_unsupported() {
  eval "$(awk '/^vm_select_iso_storage\(\)/,/^}/' "${COMMUNITY_SCRIPTS_CORE_DIR}/incus/vm-core.func")"
  expect_failure "archlinux-x86_64.iso" "not supported on Incus"
}

for test in single_storage local_storage multiple_storage explicit_storage \
  preselected_storage unattended_single unattended_multiple inactive_storage \
  no_storage invalid_preset inactive_preset status_error path_error relative_path \
  empty_path multiline_path invalid_filename missing_filename invalid_selection \
  cancellation incus_unsupported; do
  : >"$PVE_CALLS"
  : >"$ERRORS"
  if ("$test"); then
    printf 'PASS %s\n' "$test"
    passed=$((passed + 1))
  else
    printf 'FAIL %s\n' "$test" >&2
    failed=$((failed + 1))
  fi
done

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
