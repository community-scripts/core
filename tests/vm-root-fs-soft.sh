#!/usr/bin/env bash
# vm_expand_image is a soft step, but a failing virt-filesystems (libguestfs
# could not build its appliance) reached the ERR trap from inside the process
# substitution and ended k3s-vm and netbird-server runs.
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

ERRS="$(mktemp)"
trap 'rm -f "$ERRS"' EXIT
for backend in pve incus; do
  : >"$ERRS"
  out="$(
    eval "$(awk '/^(_vm_root_fs|vm_expand_image)[(][)] [{]/,/^}/' "$CORE_DIR/$backend/vm-core.func")"
    msg_warn() { echo "warn: $*"; }
    msg_ok() { echo "ok: $*"; }
    command() { [[ "$1 $2" == "-v virt-resize" ]] && return 0; builtin command "$@"; }
    virt-filesystems() { echo "libguestfs error: /usr/bin/supermin exited with error status 1." >&2; return 1; }
    set -Eeo pipefail
    trap 'echo "ERR trap: $BASH_COMMAND" >>"$ERRS"; exit 1' ERR
    vm_expand_image /tmp/image.qcow2 10G || echo "expand returned $?"
    echo "script continues"
  )"
  expect "$backend: no ERR trap" 0 "$(grep -c 'ERR trap' "$ERRS")"
  expect "$backend: the step warns and returns 1" 1 "$(grep -c '^expand returned 1$' <<<"$out")"
  expect "$backend: the run goes on" 1 "$(grep -c '^script continues$' <<<"$out")"

  size="$(
    eval "$(awk '/^_vm_root_fs[(][)] [{]/,/^}/' "$CORE_DIR/$backend/vm-core.func")"
    virt-filesystems() { printf 'Name,Type,VFS,Label,Size,Parent\n/dev/sda1,filesystem,ext4,,3000,-\n/dev/sda15,filesystem,vfat,,100,-\n'; }
    _vm_root_fs /tmp/image.qcow2
  )"
  expect "$backend: the root filesystem is still found" "3000 /dev/sda1" "$size"
done

echo "passed=${passed} failed=${failed}"
((failed == 0))
