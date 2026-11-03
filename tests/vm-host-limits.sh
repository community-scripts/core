#!/usr/bin/env bash
# What the host can run is checked before the VM is built: no /dev/kvm used to
# end the run at qm start, after the download, and a script's 4-core default
# did not start on a host with 2 threads.
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
CL="" BOLD="" DGN="" BGN="" CPUCORE="" INFO=""
passed=0 failed=0

msg_error() { echo "ERROR: $*"; }
msg_warn() { echo "WARN: $*"; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

printf 'processor\t: 0\nflags\t\t: fpu\n\nprocessor\t: 1\nflags\t\t: fpu\n' >"$TEST_DIR/cpuinfo"
export _VM_CPUINFO="$TEST_DIR/cpuinfo"

out="$(_VM_KVM_DEV="$TEST_DIR/no-kvm" kvm_check 2>&1)"
expect "no /dev/kvm stops with 236" 236 "$?"
expect "and says to enable VT-x or AMD-V" 1 "$(grep -c "Enable Intel VT-x or AMD-V" <<<"$out")"

out="$(_VM_KVM_DEV=/dev/null kvm_check 2>&1)"
expect "a KVM device passes" "0|" "$?|$out"

out="$(
  check_root() { :; }
  arch_check() { :; }
  pve_check() { :; }
  ssh_check() { echo "asked about ssh"; }
  _VM_KVM_DEV="$TEST_DIR/no-kvm" vm_preflight 2>&1
)"
expect "vm_preflight runs the check before any question" "236|0" "$?|$(grep -c "asked about ssh" <<<"$out")"

expect "host threads come from /proc/cpuinfo" 2 "$(_vm_host_cpus)"

CORE_COUNT=4
out="$(vm_fit_cores; echo "cores=$CORE_COUNT")"
expect "a default above the host is cut to its threads" "cores=2" "$(tail -n1 <<<"$out")"
expect "and says so" 1 "$(grep -c "^WARN: This host has 2 CPU threads" <<<"$out")"

CORE_COUNT=2
out="$(vm_fit_cores; echo "cores=$CORE_COUNT")"
expect "a default that fits is left alone" "cores=2" "$out"

out="$(
  _VM_CPUINFO="$TEST_DIR/none"
  CORE_COUNT=8
  vm_fit_cores
  echo "cores=$CORE_COUNT"
)"
expect "an unreadable cpuinfo changes nothing" "cores=8" "$out"

# The advanced prompt: the default shown fits the host, a larger answer is refused.
ANSWERS_FILE="$TEST_DIR/answers"
vm_dialog() {
  local box="$1"
  if [[ "$box" == inputbox ]]; then
    echo "inputbox default=$6" >>"$TEST_DIR/dialogs"
    VM_DIALOG_RESULT="$(head -n1 "$ANSWERS_FILE")"
    sed -i '1d' "$ANSWERS_FILE"
  else
    echo "$box: $3" >>"$TEST_DIR/dialogs"
  fi
  return 0
}
printf '8\n2\n' >"$ANSWERS_FILE"
: >"$TEST_DIR/dialogs"
vm_prompt_cpu_cores 4 >/dev/null
expect "the prompt offers the host's threads, not 4" "inputbox default=2" "$(head -n1 "$TEST_DIR/dialogs")"
expect "8 cores on 2 threads is refused" 1 "$(grep -c "at most 2 cores" "$TEST_DIR/dialogs")"
expect "the next answer is taken" 2 "$CORE_COUNT"

default_settings() { CORE_COUNT=4; }
vm_apply_env_overrides() { :; }
_CS_VM_PREFLIGHT_DONE=1 VM_UNATTENDED=1 vm_start_script >/dev/null 2>&1
expect "an unattended run fits the default too" 2 "$CORE_COUNT"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
