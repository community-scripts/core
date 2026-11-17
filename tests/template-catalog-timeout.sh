#!/usr/bin/env bash
# A template storage that stops answering hung the run after "Template storage
# validated" with no message, and only kill -9 ended it.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_cs_bounded[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^  _pveam_offers_template[(][)] [{]/,/^  }/' "$CORE_DIR/pve/backend.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
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
quick() { (($1 <= 3)) && echo yes || echo no; }

out="$(_cs_bounded 5 printf 'a\nb')"
expect "a quick command keeps its output" "a|b" "${out//$'\n'/|}"
_cs_bounded 5 sh -c 'exit 3'
expect "and its exit code" 3 "$?"

start=$SECONDS
_cs_bounded 1 sleep 30 >/dev/null 2>"$TEST_DIR/stderr"
expect "a command still running at the limit returns 124" 124 "$?"
sleep 0.2
expect "quietly" "" "$(cat "$TEST_DIR/stderr")"
expect "after about the limit" yes "$(quick $((SECONDS - start)))"

# Whatever outlives the kill (here a grandchild) must not keep $( ) waiting.
start=$SECONDS
out="$(_cs_bounded 1 sh -c 'sleep 30 & wait')"
expect "a process left behind does not hold the caller" yes "$(quick $((SECONDS - start)))"

msg_error() { echo "ERROR $1" >>"$TEST_DIR/msgs"; }
msg_custom() { echo "HINT $3" >>"$TEST_DIR/msgs"; }
_pveam_update() { echo update >>"$TEST_DIR/calls"; }
_pveam_available() { printf 'system          debian-13-standard_13.1-2_amd64.tar.zst\n'; }
PCT_OSTYPE=debian PCT_OSVERSION=13 ARCH=amd64 TEMPLATE_STORAGE=tank YW=""

pveam() { printf 'tank:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst  vztmpl  130000000\n'; }
_pveam_offers_template
expect "a template on the storage is found" 0 "$?"
expect "without asking the catalog" "" "$(cat "$TEST_DIR/calls" 2>/dev/null)"

pveam() { :; }
_pveam_offers_template
expect "an empty storage falls back to the catalog" 0 "$?"
expect "after updating it" update "$(cat "$TEST_DIR/calls" 2>/dev/null)"

pveam() { sleep 30; }
start=$SECONDS
eval "$(declare -f _cs_bounded | sed 's/\$1 \* 20/1 * 20/')"
(_pveam_offers_template) >/dev/null 2>&1
expect "a storage that does not answer ends the run as 'storage not accessible'" 217 "$?"
expect "within the limit" yes "$(quick $((SECONDS - start)))"
expect "naming the command" yes "$(grep -q "ERROR Template storage 'tank' does not answer: 'pveam list tank'" "$TEST_DIR/msgs" && echo yes || echo no)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
