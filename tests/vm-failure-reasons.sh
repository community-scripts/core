#!/usr/bin/env bash
# A VM failure trace has to say why: the reasons used to go to the terminal
# only (curl's error, qm's import output, every msg_warn), and the step labels
# carried the colour codes as text.
set -uo pipefail

COMMUNITY_SCRIPTS_CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export COMMUNITY_SCRIPTS_CORE_DIR
pveversion() { :; }
# shellcheck disable=SC1091
source "${COMMUNITY_SCRIPTS_CORE_DIR}/pve/vm-core.func"
# shellcheck disable=SC1091
source "${COMMUNITY_SCRIPTS_CORE_DIR}/api/exitcodes.func"
# shellcheck disable=SC1091
source "${COMMUNITY_SCRIPTS_CORE_DIR}/api/errorlog.func"
set +e -uo pipefail
trap - ERR

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
BUILD_LOG="$TEST_DIR/build.log"
color
CROSS="x" CM="v" INFO="i" TAB="  "
passed=0 failed=0
stop_spinner() { :; }
start_spinner() { :; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

msg_warn "Image step failed: hostname - cannot open /dev/kvm" 2>/dev/null
expect "msg_warn reaches the log" 1 "$(grep -c '\[WARN\] Image step failed: hostname' "$BUILD_LOG")"

curl() { return 23; }
: >"$BUILD_LOG"
vm_fetch_image "https://sourceforge.net/projects/x/files/cachyos.iso/download" "$TEST_DIR/cache/cachyos.iso" 2>/dev/null
expect "a failed download names the file, not the URL's last part" 1 "$(grep -c 'Failed to download cachyos.iso ' "$BUILD_LOG")"
expect "and says what curl ran into" 1 "$(grep -c 'curl exit 23: curl: Write error (disk full or permissions)' "$BUILD_LOG")"
expect "and leaves no partial file" "" "$(ls "$TEST_DIR/cache")"
unset -f curl

printf 'x' >"$TEST_DIR/img.qcow2.xz"
xz() { printf 'unpacked'; }
pv() { cat >/dev/null; return 1; }
: >"$BUILD_LOG"
vm_extract_image "$TEST_DIR/img.qcow2.xz" "$TEST_DIR/out/img.qcow2" 2>/dev/null
expect "pv failing to write is a failed unpack" 1 "$?"
expect "which says how much room there was" 1 "$(grep -c "Failed to unpack img.qcow2.xz (exit 1, .* free in $TEST_DIR/out)" "$BUILD_LOG")"
pv() { cat; }
vm_extract_image "$TEST_DIR/img.qcow2.xz" "$TEST_DIR/out/img.qcow2" 2>/dev/null
expect "a clean unpack still succeeds" "0|unpacked" "$?|$(cat "$TEST_DIR/out/img.qcow2")"
unset -f xz pv

qm() {
  [[ "$*" == *--help* ]] && return 0
  case "$1 $2" in
  "disk import") echo "storage 'local-lvm' is not online" >&2; return 255 ;;
  esac
  return 0
}
: >"$BUILD_LOG"
vm_import_disk 100 "$TEST_DIR/img.qcow2" local-lvm raw 2>/dev/null
expect "qm's reason for a failed import reaches the log" 1 "$(grep -c "storage 'local-lvm' is not online" "$BUILD_LOG")"
unset -f qm

# shellcheck disable=SC2016
expect "a step label loses the colour codes it carries as text" "https://example.org/a.img" \
  "$(_tm_one_line "${CL}${BL}https://example.org/a.img${CL}")"
expect "so does a log line" "[OK] Using cephfs for ISO Storage Location." \
  "$(printf '%s\n' "[OK] Using ${CL}${BL}cephfs${CL} ${GN}for ISO Storage Location." | _tm_clean_log)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
