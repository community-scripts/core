#!/usr/bin/env bash
# A VM ID typed with a trailing space reached qm create split and qm disk import
# quoted ("got '100 '"), and a mistyped bridge only failed at qm create.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(vm_prompt_vmid|vm_prompt_bridge)[(][)] [{]/,/^}/' "$CORE_DIR/pve/vm-core.func")"

passed=0 failed=0
CROSS="" RD="" CL="" CONTAINERID="" BOLD="" DGN="" BGN="" BRIDGE=""
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

ANSWERS=()
vm_dialog() {
  VM_DIALOG_RESULT="${ANSWERS[0]}"
  ANSWERS=("${ANSWERS[@]:1}")
}
exit_script() { exit 1; }
sleep() { :; }
get_valid_nextid() { echo 105; }
pct() { return 1; }
qm() { [[ "$2" == 200 ]]; }
ip() { [[ "$4" == vmbr0 || "$4" == vmbr1 ]]; }

ANSWERS=("100 ")
vm_prompt_vmid >/dev/null
expect "spaces around the ID are dropped" 100 "$VMID"

ANSWERS=("abc" "12" "200" "201")
vm_prompt_vmid >/dev/null
expect "a non-number, a too small and a used ID are asked again" 201 "$VMID"

ANSWERS=("")
vm_prompt_vmid >/dev/null
expect "an empty answer takes the next free ID" 105 "$VMID"

ANSWERS=("vmbr080" " vmbr1 ")
vm_prompt_bridge vmbr0 >/dev/null
expect "a bridge that does not exist is asked again" vmbr1 "$BRG"

ANSWERS=("")
vm_prompt_bridge vmbr0 >/dev/null
expect "an empty bridge takes the default" vmbr0 "$BRG"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
