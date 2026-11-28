#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^_FORGE_JQ_VKEY_DEF=/,/^_FORGE_JQ_VKEY=/p' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^_forge_(descriptor|strip_v|is_current|highest_version|same_shape|stable_filter|is_script_app|previous_version)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^check_for_release[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
OPT="$TEST_DIR/opt"
LOG="$TEST_DIR/log"
passed=0 failed=0

jq() { command jq "$@" | tr -d '\r'; }
msg_info() { :; }
msg_ok() { echo "ok: $*" >>"$LOG"; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
ensure_dependencies() { :; }
getent() { return 0; }
_forge_designated_release() { return 1; }
_forge_http_get() {
  local tag=v20.0.20261125
  [[ "$2" == *pdfkiln* ]] && tag=v1.5.0
  printf '[{"tag_name":"%s","prerelease":false,"draft":false}]' "$tag" >"$3"
}
# The migration reads /opt; send it to a scratch directory instead.
find() {
  if [[ "$1" == /opt ]]; then
    shift
    command find "$OPT" "$@"
  else
    command find "$@"
  fi
}

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$LOG" >&2
    failed=$((failed + 1))
  fi
}
reset() {
  rm -rf "$HOME" "$OPT"
  mkdir -p "$HOME" "$OPT"
  : >"$LOG"
}
check() {
  local rc=0
  check_for_release github "$1" "$2" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# community-scripts/core#303: the Odoo container's own file, a component checked first
reset
export NSAPP=odoo
echo 20.0.20261125 >"$OPT/Odoo_version.txt"
expect "a component is not installed" 0 "$(check pdfkiln pdfkiln/pdfkiln)"
expect "it says so" 1 "$(grep -c 'pdfkiln not installed -> 1.5.0' "$LOG")"
expect "it does not take the app's version" no "$([[ -f "$HOME/.pdfkiln" ]] && echo yes || echo no)"
expect "the app's file stays" 20.0.20261125 "$(cat "$OPT/Odoo_version.txt" 2>/dev/null)"

: >"$LOG"
expect "the app's own check still migrates it" 1 "$(check odoo odoo/odoo)"
expect "with the version from the file" 1 "$(grep -c 'No update available: odoo (20.0.20261125)' "$LOG")"
expect "the stamp holds it" 20.0.20261125 "$(cat "$HOME/.odoo" 2>/dev/null)"
expect "the file is gone" no "$([[ -f "$OPT/Odoo_version.txt" ]] && echo yes || echo no)"

# Release names that add or drop a part of the app's name are the app's own
reset
export NSAPP=paperless-ngx
echo v2.14.0 >"$OPT/Paperless-ngx_version.txt"
check paperless paperless-ngx/paperless-ngx >/dev/null
expect "a shorter release name migrates" 2.14.0 "$(cat "$HOME/.paperless" 2>/dev/null)"

# Without a known script app every release counts, as before
reset
unset NSAPP
echo 1.4.0 >"$OPT/restic_version.txt"
check restic restic/restic >/dev/null
expect "no NSAPP: the lone file migrates" 1.4.0 "$(cat "$HOME/.restic" 2>/dev/null)"

# Unchanged: two files are ambiguous, and an existing stamp wins
reset
export NSAPP=odoo
echo 20.0.1 >"$OPT/Odoo_version.txt"
echo 1.0.0 >"$OPT/other_version.txt"
check odoo odoo/odoo >/dev/null
expect "two files: none is taken" 2 "$(command find "$OPT" -type f | wc -l | tr -d ' ')"
reset
echo 20.0.20261125 >"$HOME/.odoo"
echo 19.0.1 >"$OPT/Odoo_version.txt"
check odoo odoo/odoo >/dev/null
expect "a stamp wins over the file" 20.0.20261125 "$(cat "$HOME/.odoo")"
expect "and leaves it alone" 19.0.1 "$(cat "$OPT/Odoo_version.txt")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
