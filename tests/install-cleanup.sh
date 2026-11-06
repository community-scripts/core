#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^setup_uv\(\) \{/,/^}/' "$CORE_DIR/lib/runtime.func")"
eval "$(awk '/^on_exit\(\) \{/,/^}/' "$CORE_DIR/core/error_handler.func")"
eval "$(awk '/^cleanup_lxc\(\) \{/,/^}/' "$CORE_DIR/core/core.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
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

# shellcheck disable=SC2034  # read by the eval'd helpers
STD=""
msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
msg_warn() { :; }
ensure_dependencies() { :; }
curl_with_retry() { return 1; }
_is_container_context() { return 0; }
_container_write_failure() { :; }

# setup_uv returning early (here: a failed download) must leave the caller's EXIT trap alone
mktemp() { command mktemp "$@" | tee "$TEST_DIR/uv-tmp"; }
result=$(
  trap ':' EXIT
  UV_VERSION=0.0.1 setup_uv >/dev/null 2>&1 || true
  trap -p EXIT
)
unset -f mktemp
check "setup_uv keeps the caller's EXIT trap" "trap -- ':' EXIT" "$result"
check "setup_uv removes its temp dir" "gone" "$([[ -d "$(cat "$TEST_DIR/uv-tmp")" ]] && echo left || echo gone)"

run_exit() {
  rm -f "$TEST_DIR/cleaned"
  (
    cleanup_lxc() { touch "$TEST_DIR/cleaned"; }
    _CS_UPDATE_CLEANUP="$1"
    trap on_exit EXIT
    exit "$2"
  ) || true
  [[ -e "$TEST_DIR/cleaned" ]] && echo ran || echo skipped
}
check "update exits inside update_script: cleanup runs" "ran" "$(run_exit 1 0)"
check "failed update: no cleanup" "skipped" "$(run_exit 1 1)"
check "not an update: no cleanup" "skipped" "$(run_exit "" 0)"

# An empty PATH stands in for a distro without apt-get, and keeps cleanup_lxc's find away from /tmp
mkdir "$TEST_DIR/bin"
result=$(
  PATH="$TEST_DIR/bin"
  is_alpine() { return 1; }
  pkg_clean() { echo pkg_clean; }
  cleanup_lxc 2>/dev/null
)
check "no apt-get: cleanup_lxc cleans through pkg_clean" "pkg_clean" "$result"
check "install.func does not shadow core.func's cleanup_lxc" "" "$(grep -n '^cleanup_lxc()' "$CORE_DIR/lxc/install.func" || true)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
