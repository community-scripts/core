#!/usr/bin/env bash
# A failing VM run removes the VM it created and no other, and an unattended
# VM_VMID has to be a free VM ID.
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
BUILD_LOG="$TEST_DIR/build.log"
STATE="$TEST_DIR/state"
QM_LOG="$TEST_DIR/qm.log"
export BUILD_LOG STATE QM_LOG
mkdir -p "$TEST_DIR/bin" "$STATE/vm" "$STATE/ct"
cat >"$TEST_DIR/bin/qm" <<'EOF'
#!/usr/bin/env bash
echo "qm $*" >>"$QM_LOG"
case "$1" in
status) [[ -e "$STATE/vm/$2" ]] || exit 2 ;;
create)
  [[ -e "$STATE/vm/$2" ]] && { echo "VM $2 already exists" >&2; exit 255; }
  : >"$STATE/vm/$2"
  ;;
destroy) rm -f "$STATE/vm/$2" ;;
set) [[ "$*" != *--bad* ]] || exit 255 ;;
esac
exit 0
EOF
chmod +x "$TEST_DIR/bin/qm"
PATH="$TEST_DIR/bin:$PATH"
pct() { [[ -e "$STATE/ct/$2" ]]; }

CL="" RD="" YW="" YWB="" TAB="  "
msg_error() { echo "ERROR: $*"; }
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
reset() { rm -f "$STATE"/vm/* "$STATE"/ct/*; : >"$QM_LOG"; }
removals() { grep -E '^qm (stop|destroy)' "$QM_LOG" | paste -sd'|'; }

reset
: >"$STATE/vm/100"
(set -e; trap 'error_handler $LINENO "$BASH_COMMAND"' ERR; VMID=100; false; echo never) >/dev/null 2>&1
expect "a failure before qm create leaves the VM that holds the ID alone" "" "$(removals)"
expect "and that VM still exists" 100 "$(ls "$STATE/vm")"

reset
: >"$STATE/vm/100"
out="$( (set -e; trap 'error_handler $LINENO "$BASH_COMMAND"' ERR; VMID=100; qm create "$VMID" -name test; echo never) 2>&1 )"
expect "qm create failing on a taken ID destroys nothing" "" "$(removals)"
expect "and that VM still exists" 100 "$(ls "$STATE/vm")"
expect "the failure is reported as qm create" 1 "$(grep -c 'while executing command qm create ' <<<"$out")"

reset
out="$( (set -e; trap 'error_handler $LINENO "$BASH_COMMAND"' ERR; VMID=100; qm create "$VMID" -name test; qm set "$VMID" --bad; echo never) 2>&1 )"
expect "a failure after this run's qm create stops and destroys its VM" "qm stop 100|qm destroy 100" "$(removals)"
expect "and nothing is left" "" "$(ls "$STATE/vm")"
# shellcheck disable=SC2016
expect "a later qm failure is reported as the script wrote it" 1 "$(grep -cF 'while executing command qm set "$VMID" --bad' <<<"$out")"

reset
(set -e; trap 'error_handler $LINENO "$BASH_COMMAND"' ERR; VMID=100; STD=silent; $STD qm create "$VMID" -name test; false; echo never) >/dev/null 2>&1
expect "the same for qm create run through \$STD" "qm stop 100|qm destroy 100" "$(removals)"

reset
: >"$STATE/vm/100"
: >"$STATE/ct/101"
for id in abc 99 0100 "100 "; do
  out="$( (VMID=105; VM_VMID="$id" vm_apply_env_overrides; echo "VMID=$VMID") 2>&1 )"
  rc=$?
  expect "VM_VMID '$id' stops the run" "205|1" "$rc|$(grep -c 'not a number from 100 to 999999999' <<<"$out")"
done
for id in 100 101; do
  out="$( (VMID=105; VM_VMID="$id" vm_apply_env_overrides; echo "VMID=$VMID") 2>&1 )"
  rc=$?
  expect "VM_VMID $id, already in use, stops the run" "206|1" "$rc|$(grep -c 'already in use' <<<"$out")"
done
out="$( (VMID=105; VM_VMID=102 vm_apply_env_overrides; echo "VMID=$VMID") 2>&1 )"
expect "a free VM_VMID is taken" "0|VMID=102" "$?|$out"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
