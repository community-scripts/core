#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$CORE_DIR/core/build.func"
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

line="$(grep -m1 '^unset SUDO_USER' "$BUILD" || true)"
left="$(SUDO_USER=bob SUDO_UID=1000 SUDO_GID=1000 SUDO_HOME=/home/bob SUDO_COMMAND=update \
  bash -c "${line:-:}; env | grep '^SUDO_' | cut -d= -f1 | xargs || true")"
check "build.func drops every SUDO_ variable" "" "$left"

unset_at="$(grep -n -m1 '^unset SUDO_USER' "$BUILD" | cut -d: -f1 || true)"
probes_at="$(grep -n -m1 '^_cs_start_host_probes$' "$BUILD" | cut -d: -f1)"
check "before the first child process starts" yes "$([[ -n "$unset_at" && "$unset_at" -lt "$probes_at" ]] && echo yes || echo no)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
