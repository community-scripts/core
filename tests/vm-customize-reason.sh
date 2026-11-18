#!/usr/bin/env bash
# An image step that fails has to name the reason. libguestfs puts "error:" on
# a line of its own, so the warning used to end after the step label.
set -uo pipefail

COMMUNITY_SCRIPTS_CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export COMMUNITY_SCRIPTS_CORE_DIR
pveversion() { :; }
# shellcheck disable=SC1091
source "${COMMUNITY_SCRIPTS_CORE_DIR}/pve/vm-core.func"
set +e -uo pipefail
trap - ERR

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0
CL="" BL=""
stop_spinner() { :; }
start_spinner() { :; }
msg_warn() { :; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

virt-customize() {
  cat "$FIXTURE"
  return 1
}

reason_for() {
  FIXTURE="$TEST_DIR/$1"
  _VM_PREPARE_FAILED=()
  _vm_customize "step" "$TEST_DIR/image" --run-command true
  printf '%s' "${_VM_PREPARE_FAILED[0]:-}"
}

cat >"$TEST_DIR/missing-package" <<'EOF'
Reading package lists...
E: Unable to locate package linux-modules-extra-generic
virt-customize: error:
      export DEBIAN_FRONTEND=noninteractive
      apt-get $apt_opts install 'curl' 'linux-modules-extra-generic'
    : command exited with an error

If reporting bugs, run virt-customize with debugging enabled and include the complete output:
EOF
expect "apt names the missing package" \
  "step - Unable to locate package linux-modules-extra-generic" "$(reason_for missing-package)"

cat >"$TEST_DIR/disk-full" <<'EOF'
Unpacking mesa-libgallium:amd64 (25.2.8-0ubuntu0.24.04.5) ...
dpkg: error processing archive /tmp/apt-dpkg-install-arOmcI/130-mesa-libgallium_25.2.8_amd64.deb (--unpack):
 cannot copy extracted data for './usr/lib/libgallium.so' to '/usr/lib/libgallium.so.dpkg-new': failed to write (No space left on device)
E: Sub-process /usr/bin/dpkg returned an error code (1)
virt-customize: error:
    : command exited with an error
EOF
expect "a full disk wins over dpkg's summary" "step - No space left on device" "$(reason_for disk-full)"

cat >"$TEST_DIR/apt-space" <<'EOF'
E: You don't have enough free space in /var/cache/apt/archives/.
virt-customize: error:
    : command exited with an error
EOF
expect "apt's own space check" \
  "step - You don't have enough free space in /var/cache/apt/archives/." "$(reason_for apt-space)"

cat >"$TEST_DIR/libguestfs" <<'EOF'
virt-customize: error: libguestfs error: could not create appliance through libvirt
EOF
expect "a one-line libguestfs error" \
  "step - libguestfs error: could not create appliance through libvirt" "$(reason_for libguestfs)"

printf 'something odd\n' >"$TEST_DIR/no-reason"
expect "no reason leaves the label alone" "step" "$(reason_for no-reason)"
expect "no reason survives errexit" "alive" \
  "$(set -Eeo pipefail; FIXTURE="$TEST_DIR/no-reason"; _vm_customize "step" "$TEST_DIR/image" true; echo alive)"

info_calls="$TEST_DIR/info"
msg_info() { printf '%s\n' "$1" >>"$info_calls"; }
msg_ok() { :; }
sync() { :; }
qm() {
  case "$1 ${2:-}" in
  "disk import")
    [[ "${3:-}" == "--help" ]] && return 0
    echo "Successfully imported disk as 'unused0:local-lvm:vm-950-disk-1'"
    ;;
  esac
  return 0
}
: >"$TEST_DIR/disk.qcow2"
vm_import_disk 950 "$TEST_DIR/disk.qcow2" local-lvm
expect "the import opens one message" "Importing disk.qcow2 to local-lvm" "$(cat "$info_calls")"
expect "the import still reports the volume" "local-lvm:vm-950-disk-1" "$VM_IMPORTED_DISK"

echo "passed=${passed} failed=${failed}"
((failed == 0))
