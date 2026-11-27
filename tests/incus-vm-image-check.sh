#!/usr/bin/env bash
# Issue Incus#559: from a client that drives a remote, every VM script went on
# with "Could not confirm a VM variant". An imported image was looked up on
# "local:", a daemon such a client does not have, and Incus 7 matches nothing
# when remote and filter are one argument ("images:debian/13").
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^vm_check_image[(][)] [{]/,/^}/' "$CORE_DIR/incus/vm-core.func")"

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

msg_info() { :; }
msg_ok() { echo ok >>"$TEST_DIR/out"; }
msg_warn() { echo warn >>"$TEST_DIR/out"; }
fatal() { echo fatal >>"$TEST_DIR/out"; }
# Behaves like the 7.6 client: "remote:filter" in one argument matches nothing.
incus() {
  echo "$*" >>"$TEST_DIR/asked"
  case "$1 $2" in
  "image list")
    [[ "$3" == local: && -n "${NO_LOCAL_DAEMON:-}" ]] && return 1
    [[ "$3" == *: && "${4:-}" != type=* ]] || return 0
    case "$3$4" in
    images:debian/13 | "${ON_SERVER:-}:${VM_ALIAS:-}") echo "$4" ;;
    esac
    ;;
  "image info")
    local ref="$3"
    [[ "$ref" == *:* ]] || ref="${INCUS_REMOTE:-local}:$ref"
    [[ "$ref" == images:* || "$ref" == "${ON_SERVER:-}:${KNOWN:-}" ]] || return 1
    ;;
  esac
  return 0
}
check() {
  : >"$TEST_DIR/out"
  : >"$TEST_DIR/asked"
  vm_check_image "$1"
}

INCUS_REMOTE=incus001 ON_SERVER=incus001 NO_LOCAL_DAEMON=1 VM_ALIAS=cs-haos_ova-18.4
check cs-haos_ova-18.4
expect "an imported image is looked up on the target remote" 0 "$(grep -c 'local:' "$TEST_DIR/asked")"
expect "and its VM variant is confirmed" ok "$(cat "$TEST_DIR/out")"

check images:debian/13
expect "remote and filter go as two arguments" 1 "$(grep -c '^image list images: debian/13 type=virtual-machine' "$TEST_DIR/asked")"
expect "so an image server alias is confirmed" ok "$(cat "$TEST_DIR/out")"

INCUS_REMOTE=local ON_SERVER=local NO_LOCAL_DAEMON=""
check cs-haos_ova-18.4
expect "on the server itself the imported image is confirmed too" ok "$(cat "$TEST_DIR/out")"

VM_ALIAS="" KNOWN=cs-container
check cs-container
expect "an image without a VM variant still only warns" warn "$(cat "$TEST_DIR/out")"

check cs-missing
expect "an image that is nowhere still stops" fatal "$(cat "$TEST_DIR/out")"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
