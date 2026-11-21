#!/usr/bin/env bash
# Runs ended with exit 222/223 although pveam download had just confirmed the
# template ("got correct file already"): pveam list did not show it.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$CORE_DIR/pve/backend.func"
eval "$(awk '/^_template_in_storage[(][)] [{]/,/^}/' "$BACKEND")"
eval "$(awk '/^_template_broken[(][)] [{]/,/^}/' "$BACKEND")"

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

TPL=debian-13-standard_13.6-1_amd64.tar.zst
TEMPLATE_STORAGE=nas
mkdir -p "$TEST_DIR/cache" "$TEST_DIR/root"
head -c 3000000 /dev/urandom >"$TEST_DIR/root/blob"
tar -C "$TEST_DIR/root" -czf "$TEST_DIR/good" blob

log_msg() { echo "$*" >>"$TEST_DIR/log"; }
pvesm() { echo "$TEST_DIR/cache/${2##*/}"; }
check() { _template_in_storage "$TPL" && echo yes || echo no; }

LIST="nas:vztmpl/$TPL  tzst  124.21MB" LIST_RC=0
pveam() { [[ -n "$LIST" ]] && echo "$LIST"; return "$LIST_RC"; }

expect "a listed template is there" yes "$(check)"
LIST_RC=255
expect "listed counts even when pveam list exits with an error" yes "$(check)"

LIST="" LIST_RC=0
expect "not listed and no file: missing" no "$(check)"
head -c 2000000 "$TEST_DIR/good" >"$TEST_DIR/cache/$TPL"
expect "not listed and a cut-off file: missing" no "$(check)"
cp "$TEST_DIR/good" "$TEST_DIR/cache/$TPL"
expect "not listed but a readable archive on the storage: there" yes "$(check)"
LIST="storage 'nas' is not online" LIST_RC=255
check >/dev/null
expect "and the log says what pveam list answered" 1 \
  "$(grep -c "pveam list nas (exit 255) does not show $TPL.*storage 'nas' is not online" "$TEST_DIR/log")"

pvesm() { return 2; }
LIST="" LIST_RC=0
expect "a storage pvesm cannot resolve: missing" no "$(check)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
