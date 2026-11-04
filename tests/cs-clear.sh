#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
passed=0 failed=0

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# An unattended update runs with TERM unset or dumb; clear exits 1 there and
# errexit used to end the update in header_info.
for f in core/core.func pve/vm-core.func; do
  fn="$(awk '/^_cs_clear\(\) \{/,/^}/' "$CORE_DIR/$f")"
  check "$f: TERM unset, no terminal" "ok" "$(env -u TERM bash -ec "$fn"$'\n_cs_clear; echo ok' 2>&1)"
  check "$f: TERM=dumb, no terminal" "ok" "$(TERM=dumb bash -ec "$fn"$'\n_cs_clear; echo ok' 2>&1)"
  check "$f: no escape codes into a pipe" "ok" "$(TERM=xterm bash -ec "$fn"$'\n_cs_clear; echo ok' 2>&1)"

  if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
    printf '%s\n_cs_clear; echo ok\n' "$fn" >"${TMPDIR:-/tmp}/cs-clear-$$.sh"
    out="$(env -u TERM script -qec "bash -e ${TMPDIR:-/tmp}/cs-clear-$$.sh" /dev/null | tr -d '\r')"
    check "$f: TERM unset on a terminal" "ok" "$out"
    out="$(TERM=xterm script -qec "bash -e ${TMPDIR:-/tmp}/cs-clear-$$.sh" /dev/null | tr -d '\r')"
    check "$f: clears a real terminal" "yes" "$([[ "$out" == *$'\033['*ok ]] && echo yes || echo "no: $out")"
    rm -f "${TMPDIR:-/tmp}/cs-clear-$$.sh"
  fi
done

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
