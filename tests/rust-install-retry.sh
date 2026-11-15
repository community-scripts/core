#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^setup_rust[(][)] [{]/,/^}/' "$CORE_DIR/lib/runtime.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/log"
TRIES="$TEST_DIR/tries"
passed=0 failed=0

export STD="" HOME="$TEST_DIR"
msg_info() { echo "info: $*" >>"$LOG"; }
msg_ok() { echo "ok: $*" >>"$LOG"; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
sleep() { :; }
_cs_write_cargo_profile() { :; }
cache_installed_version() { :; }
_cs_write_cargo_net() { :; }
rust_prune_toolchains() { :; }
curl() { :; }
sh() {
  echo x >>"$TRIES"
  [[ "$(wc -l <"$TRIES")" -ge "${MOCK_OK_AT:-99}" ]] || return 1
  command mkdir -p "$HOME/.cargo/bin"
  printf '#!/bin/sh\necho rustc 1.99.1\n' >"$HOME/.cargo/bin/rustc"
  printf '#!/bin/sh\necho rustup\n' >"$HOME/.cargo/bin/rustup"
  printf '#!/bin/sh\n' >"$HOME/.cargo/bin/cargo"
  chmod +x "$HOME/.cargo/bin/"*
}

run() {
  : >"$LOG"
  : >"$TRIES"
  rm -rf "$HOME/.cargo"
  (PATH="/usr/bin:/bin" setup_rust)
}
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

MOCK_OK_AT=2 run
expect "a reset on the first try is retried" "0" "$?"
expect "it took two tries" "2" "$(wc -l <"$TRIES")"

MOCK_OK_AT=99 run
expect "three failures give up" "7" "$?"
expect "after three tries" "3" "$(wc -l <"$TRIES")"
expect "and say so" "1" "$(grep -c 'error: Failed to install Rust' "$LOG")"

echo "${passed} passed, ${failed} failed"
((failed == 0))
