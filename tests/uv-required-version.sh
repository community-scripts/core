#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Only the uv pin helpers; runtime.func drags the whole engine along.
eval "$(awk '/^_uv_(required_version|release_list|ver_ge|pick_version)\(\) \{/,/^}/' "$CORE_DIR/lib/runtime.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

_uv_release_list() { printf '%s\n' 0.13.1 0.13.0 0.12.24 0.12.23 0.12.15 0.12.14 0.11.9; }

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
pin() { printf '[tool.uv]\nrequired-version = "%s"\n' "$1" >"$TEST_DIR/pyproject.toml"; }
resolve() { _uv_required_version "$TEST_DIR" || true; }

pin "==0.12.3"; check "exact pin" "0.12.3" "$(resolve)"
pin "0.12.3"; check "bare version" "0.12.3" "$(resolve)"
pin ">=0.12.15,<0.13"; check "range picks the newest 0.12" "0.12.24" "$(resolve)"
pin ">=0.12.15, <0.13"; check "spaces inside the range" "0.12.24" "$(resolve)"
pin "~=0.12.15"; check "compatible release" "0.12.24" "$(resolve)"
pin "<0.12.15"; check "upper bound only" "0.12.14" "$(resolve)"
pin ">=0.12.15,<0.13,!=0.12.24"; check "exclusion" "0.12.23" "$(resolve)"
pin ">0.13.1"; check "nothing published matches" "" "$(resolve)"
rm -f "$TEST_DIR/pyproject.toml"; check "no pin" "" "$(resolve)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
