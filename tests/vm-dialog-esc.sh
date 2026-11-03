#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Runs vm_dialog from <engine file> in a subshell; prints "<exit code>|<what it said>".
run_dialog() {
  local engine="$1" box="$2"
  (
    eval "$(awk '/^vm_dialog[(][)] [{]/,/^}/' "$CORE_DIR/$engine")"
    msg_error() { printf 'error:%s;' "$*"; }
    exit_script() { printf 'left;'; exit 0; }
    whiptail() {
      [[ -n "${MOCK_SAYS:-}" ]] && printf '%s' "$MOCK_SAYS" >&2
      return "${MOCK_RC:-0}"
    }
    tput() { [[ "$1" == cols ]] && echo "${MOCK_COLS:-80}" || echo "${MOCK_ROWS:-24}"; }
    vm_dialog "$box" "Storage Pools" "pick one" 16 60 2 a b c d 2>/dev/null
    printf 'returned %s;' "$?"
  )
  printf '|%s' "$?"
}

for engine in pve/vm-core.func incus/vm-core.func; do
  out="$(MOCK_RC=255 run_dialog "$engine" menu)"
  expect "$engine: Esc on a menu is the user leaving" "left;|0" "$out"

  out="$(MOCK_RC=255 run_dialog "$engine" yesno)"
  expect "$engine: Esc on a yes/no box too" "left;|0" "$out"

  out="$(MOCK_RC=255 MOCK_COLS=50 MOCK_ROWS=15 run_dialog "$engine" menu)"
  expect "$engine: a terminal too small is still an error" 1 "$(grep -c "error:Terminal is 50x15" <<<"$out")"

  out="$(MOCK_RC=255 MOCK_SAYS="Error opening terminal" run_dialog "$engine" menu)"
  expect "$engine: whiptail's own complaint is still an error" 1 "$(grep -c "error:whiptail: Error opening terminal" <<<"$out")"

  out="$(MOCK_RC=1 run_dialog "$engine" menu)"
  expect "$engine: Cancel still returns 1" "returned 1;|0" "$out"
done

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
