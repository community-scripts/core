#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULTS="$CORE_DIR/ui/defaults.func"
eval "$(awk '/^declare -ag VAR_(WHITELIST|RESERVED|PER_RUN)=\(/,/^\)/' "$DEFAULTS")"
for fn in _is_whitelisted_key _is_reserved_var_key load_vars_file _load_vars_file_to_map _vars_file_value \
  _defaults_sets_dirs _defaults_set_name_ok _defaults_set_file list_defaults_sets _defaults_set_summary default_var_settings; do
  eval "$(awk "/^${fn}\\(\\) \\{/,/^}/" "$DEFAULTS")"
done
eval "$(awk '/^_storage_preselect_recover\(\) \{/,/^}/' "$CORE_DIR/pve/backend.func")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
STATE="$WORK/state"
SETS="$STATE/mydefaults"
LOG="$WORK/log"
mkdir -p "$HOME" "$SETS"
passed=0 failed=0
export DEFAULT="" BOLD="" BL="" CL="" YW="" PVEHOST_NAME=node

community_scripts_dir() { echo "$STATE"; }
msg_info() { :; }
msg_ok() { :; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
msg_custom() { echo "hint: $3" >>"$LOG"; }
base_settings() { :; }
header_info() { :; }
echo_default() { :; }
choose_and_set_storage_for_file() { :; }
for v in validate_mac_address validate_vlan_tag validate_mtu validate_tags validate_timezone validate_bridge \
  validate_gateway_ip validate_sdn_vnet validate_hostname validate_ip_address; do
  eval "$v() { return 0; }"
done
is_ip_range() { return 1; }

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$LOG" >&2
    failed=$((failed + 1))
  fi
}

cat >"$STATE/default.vars" <<'EOF'
var_brg=vmbr0
var_vlan=10
var_cpu=2
var_ns=192.168.1.1
var_container_storage=local-lvm
EOF
cat >"$SETS/vlan20.vars" <<'EOF'
var_brg=vmbr1
var_vlan=20
var_net=dhcp
var_cpu=4
var_ctid=150
EOF
printf 'var_vlan=\n' >"$SETS/untagged.vars"
printf 'var_ns=10.0.0.1\nvar_tags=dmz\n' >"$SETS/DMZ_2.vars"
printf 'var_vlan=99\n' >"$SETS/not a name.vars"
printf 'var_vlan=98\n' >"$SETS/default.vars"

# $1: set name, rest: var=value for the environment; prints what the run ends up with
run() {
  local name="$1"
  shift
  (
    : >"$LOG"
    for kv in "$@"; do export "${kv?}"; done
    default_var_settings "$name" >/dev/null 2>&1 || printf 'rc=%s|' "$?"
    printf '%s|' "${var_brg-unset}" "${var_vlan-unset}" "${var_cpu-unset}" "${var_ns-unset}" "${var_net-unset}"
  )
}

check "without a set: default.vars alone" "vmbr0|10|2|192.168.1.1|unset|" "$(run "")"
check "'default' is default.vars" "vmbr0|10|2|192.168.1.1|unset|" "$(run default)"
check "in any case" "vmbr0|10|2|192.168.1.1|unset|" "$(run Default)"
check "a set wins, default.vars fills the rest" "vmbr1|20|4|192.168.1.1|dhcp|" "$(run vlan20)"
check "the environment wins over a set" "vmbr1|30|4|192.168.1.1|dhcp|" "$(run vlan20 var_vlan=30)"
check "var_defaults picks the set" "vmbr1|20|4|192.168.1.1|dhcp|" "$(run "" var_defaults=vlan20)"
check "var_defaults=default is default.vars" "vmbr0|10|2|192.168.1.1|unset|" "$(run "" var_defaults=default)"
check "an empty value switches a default.vars setting off" "vmbr0||2|192.168.1.1|unset|" "$(run untagged)"
check "a name may carry capitals and _" "vmbr0|10|2|10.0.0.1|unset|" "$(run DMZ_2)"

check "an unknown set stops the run, nothing is loaded" "rc=1|unset|unset|unset|unset|unset|" "$(run vlan99)"
run vlan99 >/dev/null
check "it names the file it looked for" 1 "$(grep -c "mydefaults/vlan99.vars is missing" "$LOG")"
check "and what is there" 1 "$(grep -c 'Available: default DMZ_2 untagged vlan20' "$LOG")"
check "a path is not a name" "rc=1|unset|unset|unset|unset|unset|" "$(run ../default)"
check "nor is a name with a space" "rc=1|unset|unset|unset|unset|unset|" "$(run "not a name")"
check "nor one of 33 characters" "rc=1|unset|unset|unset|unset|unset|" "$(run aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)"

run vlan20 >/dev/null
check "a reserved key in a set is reported" 1 "$(grep -c 'var_ctid in .*vlan20.vars is ignored' "$LOG")"
check "the set file is exported for later steps" "$SETS/vlan20.vars" "$(default_var_settings vlan20 >/dev/null 2>&1 && echo "$CS_DEFAULTS_SET_FILE")"
check "and gone without a set" "" "$(export CS_DEFAULTS_SET_FILE=stale && default_var_settings "" >/dev/null 2>&1 && echo "${CS_DEFAULTS_SET_FILE-}")"

check "sets are listed sorted, files that are no names left out" "DMZ_2 untagged vlan20" "$(list_defaults_sets | paste -sd' ')"
check "a summary names bridge, VLAN and address" "vmbr1, VLAN 20, dhcp" "$(_defaults_set_summary "$SETS/vlan20.vars")"
check "or counts the settings" "2 settings" "$(_defaults_set_summary "$SETS/DMZ_2.vars")"
printf '#var_brg=
' >"$WORK/new.vars"
check "a new set is empty" "empty" "$(_defaults_set_summary "$WORK/new.vars")"
check "var_defaults is never read from a file" yes "$(_is_reserved_var_key var_defaults && echo yes)"

# A stale storage is corrected in the file it came from
select_storage() { export STORAGE_RESULT=tank; }
whiptail() { echo "$*" >>"$LOG"; }
_write_storage_to_vars() { echo "write $1 $2 $3" >>"$LOG"; }
recover() {
  : >"$LOG"
  CS_DEFAULT_VARS_FILE="$STATE/default.vars" CS_DEFAULTS_SET_FILE="${1:-}" _storage_preselect_recover container local-lvm >/dev/null 2>&1
  grep -o 'write .*' "$LOG"
}
printf 'var_container_storage=local-lvm\n' >"$SETS/fast.vars"
check "a storage from default.vars is corrected there" "write $STATE/default.vars var_container_storage tank" "$(recover "$SETS/vlan20.vars")"
check "one from the set in the set" "write $SETS/fast.vars var_container_storage tank" "$(recover "$SETS/fast.vars")"
recover "$SETS/fast.vars" >/dev/null
check "and the question names that file" 1 "$(grep -c 'var_container_storage in fast.vars still points' "$LOG")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
