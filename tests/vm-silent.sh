#!/usr/bin/env bash
# The VM engine's silent() hands a failure back to the caller. It used to exit
# the run itself, so `$STD cmd || true` ended every VM script whose host could
# not run apt-get update, and the trap it re-armed had lost the script's line.
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
CL="" TAB="  " YWB="" RD="" YW=""
VMID=""
passed=0 failed=0

msg_error() { echo "ERROR: $*"; }
msg_custom() { echo "CMD: $3"; }
msg_warn() { echo "WARN: $*"; }
post_update_to_api() { echo "POST $1 $2"; }
cleanup_vmid() { :; }
explain_exit_code() { echo "explained $1"; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# A failure the script handles stays handled.
out="$( (set -e; trap 'echo TRAPPED; exit 9' ERR; silent sh -c 'echo boom >&2; exit 100' || true; echo "carried on") 2>&1 )"
expect "a handled failure does not end the run" 1 "$(grep -c 'carried on' <<<"$out")"
expect "the ERR trap stays quiet for it" 0 "$(grep -c TRAPPED <<<"$out")"
expect "nothing is reported for it" 0 "$(grep -c 'ERROR:' <<<"$out")"

# An unhandled one reaches the script's own trap with the command's code.
: >"$BUILD_LOG"
out="$( (set -e; trap 'error_handler $LINENO "$BASH_COMMAND"' ERR; silent sh -c 'echo boom >&2; exit 100'; echo "never") 2>&1 )"
rc=$?
expect "the run ends with the command's code" 100 "$rc"
expect "the handler posts that code" 1 "$(grep -c 'POST failed 100' <<<"$out")"
expect "the command is the real one, not the wrapper" 1 "$(grep -c '^CMD: sh -c echo boom' <<<"$out")"
expect "the explanation is shown" 1 "$(grep -c 'exit code 100 (explained 100)' <<<"$out")"
expect "the log tail is shown" 1 "$(grep -c '^boom$' <<<"$out")"
expect "nothing runs after it" 0 "$(grep -c never <<<"$out")"

# The script's trap survives the call.
out="$( (trap 'echo MINE' ERR; silent true; trap -p ERR) )"
expect "the script's ERR trap is kept" 1 "$(grep -c MINE <<<"$out")"

# A handled failure is not pinned on the next, unrelated one.
out="$( (set -e; trap 'error_handler $LINENO "$BASH_COMMAND"' ERR; silent sh -c 'exit 100' || true
  false; echo "never") 2>&1 )"
rc=$?
expect "the later failure keeps its own code" 1 "$rc"
expect "the handled command is not blamed" 0 "$(grep -c 'CMD:' <<<"$out")"
expect "the later command is named" 1 "$(grep -c 'while executing command .*false' <<<"$out")"

# The post-creation trap reports the same way.
out="$( (set -e; VM_CREATED=1; trap 'vm_post_create_error $LINENO "$BASH_COMMAND"' ERR; silent sh -c 'echo late >&2; exit 3') 2>&1 )"
rc=$?
expect "a failure after creation keeps the code" 3 "$rc"
expect "and names the real command" 1 "$(grep -c '^CMD: sh -c echo late' <<<"$out")"
expect "and leaves the VM in place" 1 "$(grep -c 'left in place' <<<"$out")"

echo "$passed passed, $failed failed"
((failed == 0))
