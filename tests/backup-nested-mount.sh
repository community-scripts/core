#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(create_backup|restore_backup)\(\) \{/,/^}/' "$CORE_DIR/lib/system.func")"
eval "$(awk '/^_cs_clean_target_dir\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(realpath "$(mktemp -d)")"
trap 'chmod -R u+w "$TEST_DIR" 2>/dev/null; rm -rf -- "$TEST_DIR"' EXIT
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

msg_info() { :; }
msg_ok() { :; }
msg_error() { echo "ERROR $*" >&2; }
msg_warn() { :; }

APP_DIR="$TEST_DIR/etc/app"
MOUNTED=()
# Stands in for /proc/self/mountinfo: lists MOUNTED entries below the directory.
_cs_mounts_under() {
  local -n _found="$2"
  local m
  _found=()
  for m in "${MOUNTED[@]}"; do
    [[ "$m" == "$1"/* ]] && _found+=("$m")
  done
  return 0
}
listing() { (cd "$APP_DIR" && find . -type f | LC_ALL=C sort | tr '\n' ' '); }

NSAPP=app
BACKUP_DIR="$TEST_DIR/store"

setup() {
  chmod -R u+w "$TEST_DIR/etc" 2>/dev/null || true
  rm -rf "$TEST_DIR/etc" "$BACKUP_DIR"
  mkdir -p "$APP_DIR/unseal"
  echo cfg >"$APP_DIR/app.hcl"
  echo env >"$APP_DIR/app.env"
  echo secret >"$APP_DIR/unseal/key"
}

setup
create_backup "$APP_DIR"
echo changed >"$APP_DIR/app.hcl"
echo leftover >"$APP_DIR/added"
restore_backup
check "without a mount below, restore replaces the directory" "./app.env ./app.hcl ./unseal/key " "$(listing)"
check "without a mount below, the old content is back" "cfg" "$(cat "$APP_DIR/app.hcl")"

setup
MOUNTED=("$APP_DIR/unseal")
create_backup "$APP_DIR"
check "a mount below stays out of the store" "no" "$([[ -e "$BACKUP_DIR/files$APP_DIR/unseal/key" ]] && echo yes || echo no)"
check "the rest is in the store" "cfg" "$(cat "$BACKUP_DIR/files$APP_DIR/app.hcl")"

rm -f "$APP_DIR/app.hcl" "$APP_DIR/app.env"
echo leftover >"$APP_DIR/added"
echo other >"$APP_DIR/unseal/key"
chmod a-w "$APP_DIR/unseal"
restore_backup
chmod u+w "$APP_DIR/unseal"
check "restore puts the files back around the mount" "./app.env ./app.hcl ./unseal/key " "$(listing)"
check "restore leaves the mounted content alone" "other" "$(cat "$APP_DIR/unseal/key")"
check "restore removes the store" "no" "$([[ -e "$BACKUP_DIR" ]] && echo yes || echo no)"

setup
MOUNTED=("$APP_DIR/we[ir]d*dir")
mkdir -p "$APP_DIR/we[ir]d*dir" "$APP_DIR/weid*dir"
echo m >"$APP_DIR/we[ir]d*dir/f"
echo n >"$APP_DIR/weid*dir/f"
create_backup "$APP_DIR"
check "a mount name with glob characters is excluded literally" "no" "$([[ -e "$BACKUP_DIR/files$APP_DIR/we[ir]d*dir/f" ]] && echo yes || echo no)"
check "a sibling the glob would match is still backed up" "n" "$(cat "$BACKUP_DIR/files$APP_DIR/weid*dir/f")"
MOUNTED=()

echo "${passed} passed, ${failed} failed"
((failed == 0))
