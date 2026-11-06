#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULTS="$CORE_DIR/ui/defaults.func"
eval "$(awk '/^declare -ag VAR_(WHITELIST|RESERVED)=\(/,/^\)/' "$DEFAULTS")"
for fn in _is_whitelisted_key _is_reserved_var_key load_vars_file _load_vars_file_to_map; do
  eval "$(awk "/^${fn}\\(\\) \\{/,/^}/" "$DEFAULTS")"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WARNINGS="$WORK/warnings"
msg_info() { :; }
msg_ok() { :; }
msg_warn() { echo "$*" >>"$WARNINGS"; }
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

cat >"$WORK/test.vars" <<'EOF'
var_cpu=4
var_foo_port=8080
var_foo_name="My App"
var_ctid=150
var_external_installer=yes
var_Upper=1
EOF

# $1: app_keys; prints the variables a load leaves set
loaded() {
  (
    : >"$WARNINGS"
    load_vars_file "$WORK/test.vars" no "" "$1"
    printf '%s|' "${var_cpu:-}" "${var_foo_port:-}" "${var_foo_name:-}" "${var_ctid:-}" "${var_external_installer:-}" "${var_Upper:-}"
  )
}

check "default.vars takes whitelisted keys only" "4||||||" "$(loaded no)"
check "an app file also takes the app's own keys" "4|8080|My App||||" "$(loaded yes)"
loaded yes >/dev/null
check "each reserved key is reported" 2 "$(grep -c 'is ignored' "$WARNINGS")"

_load_vars_file_to_map "$WORK/test.vars"
check "the map keeps the app's own keys" 8080 "${_VARS_IN[var_foo_port]:-}"
check "the map drops reserved keys" "" "${_VARS_IN[var_ctid]:-}${_VARS_IN[var_external_installer]:-}"

for key in "${VAR_WHITELIST[@]}"; do
  if _is_reserved_var_key "$key"; then
    check "$key is in one list only" no yes
  fi
done

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
