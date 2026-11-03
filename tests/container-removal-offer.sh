#!/usr/bin/env bash
# The error handler offers to remove the container this run created, never one
# an add-on was pointed at, and its prompt does not end the run on its own.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(_eh_offer_container_removal|_eh_destroy_container)[(][)] [{]/,/^}/' "$CORE_DIR/core/error_handler.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CALLS="$TEST_DIR/pct.calls"
passed=0 failed=0

pct() { echo "$*" >>"$CALLS"; }
_eh_info() { :; }
_eh_ok() { :; }
_eh_warn() { :; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# An add-on picked an existing container: no prompt, no pct call at all.
: >"$CALLS"
out="$(CTID=101 _eh_offer_container_removal 2>&1)"
expect "a container this run did not create is left alone" "" "$(cat "$CALLS")"
expect "and nothing is asked" "" "$out"

: >"$CALLS"
out="$(CTID=101 _CS_CREATED_CTID=105 _eh_offer_container_removal 2>&1)"
expect "a different created container does not count" "" "$(cat "$CALLS")"

# The created container is offered. Without a terminal the read fails; under
# errexit that used to end the run with the read's code instead of the real one.
# setsid drops the controlling terminal, so a local run does not wait 60s.
: >"$CALLS"
export CALLS
export -f _eh_offer_container_removal _eh_destroy_container pct _eh_info _eh_ok _eh_warn
detach=()
command -v setsid >/dev/null 2>&1 && detach=(setsid -w)
rc=0
"${detach[@]}" bash -c 'set -e; CTID=105 _CS_CREATED_CTID=105 _eh_offer_container_removal >/dev/null 2>&1; exit 7' </dev/null || rc=$?
expect "the created container is checked" "status 105" "$(head -n1 "$CALLS")"
expect "a failed read keeps it" 0 "$(grep -c destroy "$CALLS")"
expect "and hands back to the caller under errexit" 7 "$rc"

echo "$passed passed, $failed failed"
((failed == 0))
