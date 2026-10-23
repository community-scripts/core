#!/usr/bin/env bash
# Isolated engine regression tests. No guest, host config, network, or firewall writes.
set -eo pipefail
CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# == 0 ]]; then
  failed=0 passed=0
  for scenario in legacy-pve legacy-incus incus-reject bounds holes generic-1200 generic-3000 generic-high-id local-orphan empty-cluster api-failure malformed-resources exhausted explicit-id tokens invalid-templates ipv6 defaults global-defaults precedence env-precedence save-reload save-ipv6-bounds save-ipv6-mac save-ipv6-all save-ipv6-legacy wizard wizard-accept wizard-id-change wizard-clear-mac ipv6-literal-implicit ipv6-literal-methods wizard-back-edits wizard-back-clear wizard-modes wizard-modes-static wizard-cancel-ipv6 final-net0 late-collision pct-collision; do
    if bash "$0" "$scenario"; then
      echo "PASS $scenario"
      passed=$((passed + 1))
    else
      echo "FAIL $scenario" >&2
      failed=$((failed + 1))
    fi
  done
  echo "$passed passed, $failed failed"
  ((failed == 0))
  exit $?
fi

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
# Tests must not inherit the operator's policy or proxy configuration.
for key in ${!var_@} ${!_IDENTITY_@}; do unset "$key"; done
if [[ "$1" == env-precedence ]]; then
  export var_ctid_min=612 var_mac=02:00:00:00:99:09 var_net=dhcp
fi
_cs_source_func() { source "$CORE_DIR/$1"; }
source "$CORE_DIR/ui/build-ui.func" >/dev/null 2>&1
trap - ERR EXIT
trap 'rm -rf -- "$TEST_DIR"' EXIT
set -eo pipefail
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { echo "$*" >&2; }
ensure_dependencies() { command -v jq >/dev/null; }
lvs() { :; }
pvesh() {
  case "$*" in
  'get /cluster/nextid') echo 900 ;;
  'get /cluster/resources --type vm --output-format json')
    [[ "${API_FAIL:-0}" == 0 ]] || return 42
    echo "${RESOURCES:-[]}"
    ;;
  *)
    echo "Unexpected pvesh call: $*" >&2
    return 1
    ;;
  esac
}
resolve_os_version() { :; }
detect_lxc_platform() { echo pve; }
APP=Identity NSAPP=identity NEXTID=900 timezone=UTC var_os=debian var_version=13

same() { [[ "$1" == "$2" ]] || {
  echo "Expected <$1>, got <$2>" >&2
  return 1
}; }
reject() {
  if ("$@") >"$TEST_DIR/rejected" 2>&1; then
    echo "Unexpected success: $*" >&2
    return 1
  fi
}
assert_lacks() {
  # Negated commands suppress errexit and later assertions can hide failure.
  # Exit explicitly on a match and also propagate grep's I/O errors.
  if grep -Fq -- "$1" "$2"; then
    echo "Unexpected <$1> in $2" >&2
    exit 1
  else
    local rc=$?
    if ((rc != 1)); then exit "$rc"; fi
  fi
}
policy() {
  var_ctid_min=604 var_ctid_max=9999
  var_mac_template='02:00:00:00:{id_hi2}:{id_lo2}'
}
static_policy() {
  policy
  var_net_template='10.20.{id_hi}.{id_lo}/16'
  var_ipv6_template='2001:db8::{id_hi}:{id_lo}/64'
}
backend() {
  source "$CORE_DIR/pve/backend.func"
  trap - ERR EXIT
  trap 'rm -rf -- "$TEST_DIR"' EXIT
}
# Exercise the complete real build_container through its final PCT_OPTIONS.
# Stop at the creation boundary, before any guest or host writes.
net0_capture() {
  backend
  trap - EXIT
  lxc_os_support_check() { :; }
  _cs_fetch_text() { :; }
  cs_testing_state() { :; }
  pvesm() { :; }
  pct_timezone() { echo UTC; }
  create_lxc_container() {
    printf '%s\n' "$PCT_OPTIONS" >"$TEST_DIR/pct-options"
    rm -rf -- "$TEMP_DIR"
    exit 0
  }
  DIAGNOSTICS=no RANDOM_UUID=test EXECUTION_ID=test SESSION_ID=test BUILD_LOG=/dev/null
  COMMUNITY_SCRIPTS_CORE_URL=unused IPV6_GATE=""
  build_container
}
# Actual wizard, with whiptail's response stream and noninteractive host stubs.
wizard_run() {
  local wizard_pid="$BASHPID"
  populate_advanced_bridge_menu() { BRIDGES=vmbr0; }
  tput() { :; }
  timedatectl() { :; }
  configure_ssh_settings() { :; }
  validate_bridge() { [[ "$1" == vmbr0 ]]; }
  whiptail() {
    local title="" previous="" menu_default="" arg
    for arg in "$@"; do
      [[ "$previous" == --title ]] && title="$arg"
      [[ "$previous" == --default-item ]] && menu_default="$arg"
      previous="$arg"
    done
    if [[ "${WIZARD_ACCEPT:-0}" == 1 ]]; then
      case "$title" in
      'STATIC IPv4 ADDRESS') same "$NET" "${!#}" || exit 96 ;;
      'STATIC IPv6 ADDRESS') same "$IPV6_ADDR" "${!#}" || exit 96 ;;
      'MAC ADDRESS') same "${MAC#*,hwaddr=}" "${!#}" || exit 96 ;;
      'IPv4 CONFIGURATION' | 'IPv6 CONFIGURATION') [[ " $* " == *' --default-item static '* ]] || exit 96 ;;
      esac
    fi
    printf '%s\n' "$title" >>"$TEST_DIR/dialogs"
    if [[ $(wc -l <"$TEST_DIR/dialogs") -gt 90 ]]; then
      tail -12 "$TEST_DIR/dialogs" >&2
      kill -TERM "$wizard_pid"
      return 98
    fi
    if [[ -n "${WIZARD_NAVIGATION:-}" ]]; then
      local visit
      visit=$(grep -c -x "$title" "$TEST_DIR/dialogs")
      printf '%s|%s|%s\n' "$title" "$menu_default" "${!#}" >>"$TEST_DIR/dialog-state"
      case "$title" in
      'IPv4 CONFIGURATION')
        if [[ "$WIZARD_NAVIGATION" == back-* ]]; then
          if ((visit == 1)); then echo static >&2; else echo "$menu_default" >&2; fi
        elif ((visit == 1)) || [[ "$WIZARD_NAVIGATION" == modes || "$WIZARD_NAVIGATION" == cancel-ipv6 ]]; then
          echo dhcp >&2
        else
          echo static >&2
        fi
        return 0
        ;;
      'STATIC IPv4 ADDRESS')
        if ((visit == 1)); then echo 10.20.9.3/16 >&2; else echo "${!#}" >&2; fi
        return 0
        ;;
      'IPv6 CONFIGURATION')
        if ((visit == 1)); then return 1; fi # Back to IPv4 after its accepted edit/mode change.
        if [[ "$WIZARD_NAVIGATION" == back-* ]]; then
          if ((visit == 2)); then echo static >&2; else echo "$menu_default" >&2; fi
        elif ((visit == 2)); then
          echo "${WIZARD_IPV6_MODE:-dhcp}" >&2
        elif [[ "$WIZARD_NAVIGATION" == modes-static || ("$WIZARD_NAVIGATION" == cancel-ipv6 && "$visit" == 3) ]]; then
          echo static >&2
        else
          echo "$menu_default" >&2
        fi
        return 0
        ;;
      'STATIC IPv6 ADDRESS')
        if [[ "$WIZARD_NAVIGATION" == cancel-ipv6 ]]; then return 1; fi
        if ((visit == 1)); then echo 2001:db8::93/64 >&2; else echo "${!#}" >&2; fi
        return 0
        ;;
      'MTU SIZE')
        if ((visit == 1)); then return 1; fi # Back to IPv6 after its accepted edit/mode change.
        ;;
      'MAC ADDRESS')
        if ((visit == 1)); then
          if [[ "$WIZARD_NAVIGATION" == back-clear ]]; then echo '' >&2; else echo 02:00:00:00:99:03 >&2; fi
        else
          echo "${!#}" >&2
        fi
        return 0
        ;;
      'VLAN TAG')
        if ((visit == 1)); then return 1; fi # Back to MAC, including intentional clearing.
        ;;
      esac
    fi
    case "$title" in
    'CONTAINER TYPE') echo 1 >&2 ;;
    'ROOT PASSWORD') echo '' >&2 ;;
    'CONTAINER ID') echo "${WIZARD_ID:-$CT_ID}" >&2 ;;
    HOSTNAME) echo identity >&2 ;;
    'DISK SIZE') echo 4 >&2 ;;
    'CPU CORES') echo 1 >&2 ;;
    'RAM SIZE') echo 1024 >&2 ;;
    'IPv4 CONFIGURATION') echo static >&2 ;;
    'STATIC IPv4 ADDRESS') echo "${WIZARD_NET:-$NET}" >&2 ;;
    'GATEWAY IP') echo 10.20.0.1 >&2 ;;
    'IPv6 CONFIGURATION') echo static >&2 ;;
    'STATIC IPv6 ADDRESS') echo "${WIZARD_IPV6:-$IPV6_ADDR}" >&2 ;;
    'IPv6 GATEWAY') echo '' >&2 ;;
    'MAC ADDRESS') echo "${WIZARD_MAC-${MAC#*,hwaddr=}}" >&2 ;;
    'VLAN TAG') echo 6 >&2 ;;
    'CONTAINER TAGS') echo community-script >&2 ;;
    'CONTAINER TIMEZONE') echo UTC >&2 ;;
    'NESTING SUPPORT' | 'CONFIRM SETTINGS') return 0 ;;
    'MTU SIZE' | 'DNS SEARCH DOMAIN' | 'DNS SERVER' | 'MOUNT FILESYSTEMS' | 'POST-INSTALL HOOK (HOST)') echo '' >&2 ;;
    'FUSE SUPPORT' | 'TUN/TAP SUPPORT' | 'GPU PASSTHROUGH' | 'KEYCTL SUPPORT' | 'APT CACHER PROXY' | 'HTTP/HTTPS PROXY' | 'HOST CA INHERITANCE' | 'CONTAINER PROTECTION' | 'DEVICE NODE CREATION' | 'VERBOSE MODE') return 1 ;;
    *)
      echo "Unexpected wizard dialog: $title / $*" >&2
      exit 99
      ;;
    esac
  }
  # Older wizard arithmetic is not errexit-safe (e.g. ((STEP++))).
  set +e
  advanced_settings >"$TEST_DIR/wizard-output"
  local rc=$?
  set -e
  return "$rc"
}

case "$1" in
legacy-pve)
  base_settings
  same 900 "$CT_ID"
  same dhcp "$NET"
  same '' "$MAC"
  same none "$IPV6_METHOD"
  same 900 "$(get_valid_container_id)"
  cat <<'VARS' >"$TEST_DIR/legacy.vars"
var_ipv6_static=2001:db8::42/64
VARS
  load_vars_file "$TEST_DIR/legacy.vars" yes
  same '' "${var_ipv6_static:-}"
  backend
  pct() { echo "$1 $2" >"$TEST_DIR/pct-calls"; }
  _pct_create 613 ignored
  same 'create 613' "$(cat "$TEST_DIR/pct-calls")"
  ;;
legacy-incus | incus-reject)
  # Use the actual Incus entry point and its identifier overrides.
  _INCUS_CORE_FUNC_LOADED=1 _INCUS_TOOLS_FUNC_LOADED=1
  source "$CORE_DIR/incus/build.func"
  trap - ERR EXIT SIGHUP SIGINT SIGTERM
  trap 'rm -rf -- "$TEST_DIR"' EXIT
  resolve_os_version() { :; }
  incus_container_exists() { return 1; }
  incus_pick_default_network() { echo incusbr0; }
  NEXTID=identity
  if [[ "$1" == incus-reject ]]; then
    for option in var_ctid_min var_mac_template var_net_template var_ipv6_template; do
      if [[ "$option" == var_ctid_min ]]; then value=604; else value='{id}'; fi
      (
        export "$option=$value"
        reject base_settings
      )
    done
  else
    cat <<'VARS' >"$TEST_DIR/incus.vars"
var_cpu=2
var_net=dhcp
VARS
    load_vars_file "$TEST_DIR/incus.vars" yes
    base_settings
    same 2 "$CORE_COUNT"
    same identity "$CT_ID"
    same incusbr0 "$BRG"
    same dhcp "$NET"
    same '' "$MAC"
    same identity "$(get_valid_container_id identity)"
  fi
  ;;
bounds)
  var_ctid_min=604 var_ctid_max=606
  same 604 "$(get_valid_container_id)"
  for value in 99 0604 1000000000 '1+603' 999999999999999999999999; do
    (
      var_ctid_min="$value"
      reject get_valid_container_id
    )
  done
  var_ctid_min=607
  reject get_valid_container_id
  ;;
local-orphan)
  var_ctid_min=604 var_ctid_max=606
  lvs() { echo vm-604-disk-0; }
  same 605 "$(get_valid_container_id)"
  ;;
holes)
  var_ctid_min=604 var_ctid_max=620
  RESOURCES='[{"vmid":604,"type":"qemu","node":"other"},{"vmid":606,"type":"lxc","node":"other"},{"vmid":610,"type":"qemu"}]'
  same 605 "$(get_valid_container_id)"
  base_settings
  same 605 "$CT_ID"
  ;;
generic-1200)
  static_policy
  var_ctid_min=1200 var_ctid_max=1299 var_vlan=42
  RESOURCES='[{"vmid":1200,"type":"qemu","node":"other"}]'
  same 1201 "$(get_valid_container_id)"
  base_settings
  same 1201 "$CT_ID"
  same 02:00:00:00:12:01 "$MAC"
  same 10.20.12.1/16 "$NET"
  same 2001:db8::12:1/64 "$IPV6_ADDR"
  (net0_capture)
  grep -q -- 'hwaddr=02:00:00:00:12:01,ip=10.20.12.1/16,tag=42,ip6=2001:db8::12:1/64' "$TEST_DIR/pct-options"
  ;;
generic-3000)
  static_policy
  var_ctid_min=3000 var_ctid_max=3999 var_vlan=77
  var_mac_template='02:00:00:01:{id_hi2}:{id_lo2}'
  # Mixed remote VM/CT occupancy below a hole, with another guest above it.
  RESOURCES=$(jq -n '[range(3000;3042) | {vmid:., type:(if . % 2 == 0 then "qemu" else "lxc" end), node:"other"}] + [{vmid:3043,type:"qemu",node:"other"}]')
  same 3042 "$(get_valid_container_id)"
  base_settings
  same 3042 "$CT_ID"
  same 02:00:00:01:30:42 "$MAC"
  same 10.20.30.42/16 "$NET"
  same 2001:db8::30:42/64 "$IPV6_ADDR"
  (net0_capture)
  grep -q -- 'hwaddr=02:00:00:01:30:42,ip=10.20.30.42/16,tag=77,ip6=2001:db8::30:42/64' "$TEST_DIR/pct-options"
  ;;
generic-high-id)
  # Allocation has the PVE ID limit, independent of any MAC template's limit.
  var_ctid_min=20012 var_ctid_max=20099
  RESOURCES='[{"vmid":20013,"type":"lxc","node":"other"}]'
  same 20012 "$(get_valid_container_id)"
  base_settings
  same 20012 "$CT_ID"
  same '' "$MAC"
  same dhcp "$NET"
  same '' "${_IDENTITY_BOUND_ID:-}"
  same 20014 "$(get_valid_container_id 20014)"
  var_ipv6_template='2001:db8::{id_hi}:{id_lo}/64'
  var_vlan=123
  base_settings
  same 20012 "$CT_ID"
  same 2001:db8::200:12/64 "$IPV6_ADDR"
  same '' "$MAC"
  same dhcp "$NET"
  (net0_capture)
  grep -q -- 'bridge=vmbr0,ip=dhcp,tag=123,ip6=2001:db8::200:12/64' "$TEST_DIR/pct-options"
  reject _identity_render '02:00:00:00:{id_hi2}:{id_lo2}' 20012 mac
  grep -q 'without truncation' "$TEST_DIR/rejected"
  ;;
empty-cluster)
  var_ctid_min=604 var_ctid_max=604
  RESOURCES='[ ]'
  same 604 "$(get_valid_container_id)"
  # A standalone assignment under errexit must also succeed for [].
  selected=$(get_valid_container_id)
  same 604 "$selected"
  ;;
api-failure)
  var_ctid_min=604 API_FAIL=1
  reject get_valid_container_id
  grep -q 'refusing to guess' "$TEST_DIR/rejected"
  var_ctid=612
  reject base_settings
  ;;
malformed-resources)
  var_ctid_min=604
  for RESOURCES in null '{}' '' '[{}]' '[{"vmid":"604","type":"qemu"}]' '[{"vmid":604.5,"type":"lxc"}]' '[{"vmid":604,"type":"node"}]' '[{"vmid":1,"type":"qemu"}]' 'garbage'; do
    # pvesh stub defaults only unset resources, not empty, in this scenario.
    pvesh() { echo "$RESOURCES"; }
    reject get_valid_container_id
  done
  ;;
exhausted)
  var_ctid_min=604 var_ctid_max=605
  RESOURCES='[{"vmid":604,"type":"lxc"},{"vmid":605,"type":"qemu"}]'
  reject get_valid_container_id
  # Inclusive upper boundary.
  RESOURCES='[{"vmid":604,"type":"lxc"}]'
  same 605 "$(get_valid_container_id)"
  ;;
explicit-id)
  policy
  var_ctid=612
  base_settings
  same 612 "$CT_ID"
  same 02:00:00:00:06:12 "$MAC"
  unset _IDENTITY_BOUND_ID
  var_ctid=603
  base_settings
  same 603 "$CT_ID"
  same 02:00:00:00:06:03 "$MAC"
  unset _IDENTITY_BOUND_ID
  var_ctid=10000 var_mac=02:00:00:00:99:09
  base_settings
  same 10000 "$CT_ID"
  same 02:00:00:00:99:09 "$MAC"
  ;;
tokens)
  same 02:00:00:00:06:12 "$(_identity_render '02:00:00:00:{id_hi2}:{id_lo2}' 612 mac)"
  same 10.20.6.12/16 "$(_identity_render '10.20.{id_hi}.{id_lo}/16' 612 net)"
  same 192.0.2.150/24 "$(_identity_render '192.0.2.{id}/24' 150 net)"
  same 192.0.2.104/24 "$(_identity_render '192.0.2.{id}/24' 104 net)"
  same 02:00:00:00:06:04 "$(_identity_render '02:00:00:00:{id_hi2}:{id_lo2}' 604 mac)"
  same 02:00:00:00:99:99 "$(_identity_render '02:00:00:00:{id_hi2}:{id_lo2}' 9999 mac)"
  ;;
invalid-templates)
  reject _identity_render '02:00:00:00:{id_hi2}:{id_lo2}' 10000 mac
  reject _identity_render '02:00:00:00:00:{id_lo2}' 612 mac
  reject _identity_render '02:00:00:00:{id_hi2}:{unknown}' 612 mac
  reject _identity_render '10.20.{id_hi}.{id_lo}/16' 999999999 net
  reject _identity_render '10.20.08.{id_lo}/16' 612 net
  reject _identity_render '10.20.1.{id_lo}/033' 612 net
  reject _identity_render '10.20.1.$(touch /tmp/identity-unsafe)' 612 net
  reject _identity_render '10.20.{id_hi}.{id_lo}/24' 700 net
  reject _identity_render '192.0.2.{id}/24' 255 net
  same 192.0.2.100/31 "$(_identity_render '192.0.2.{id}/31' 100 net)"
  same 192.0.2.100/32 "$(_identity_render '192.0.2.{id}/32' 100 net)"
  reject _identity_render '2001:db8::{id}/64' 999999 ipv6
  ;;
ipv6)
  _identity_validate_address ipv6 1:2:3:4:5:6:7::/64
  _identity_validate_address ipv6 ::/128
  reject _identity_validate_address ipv6 1:2:3:4:5:6:7:8::/64
  reject _identity_validate_address ipv6 2001:db8::1/999999999999999999999
  for template in '2001:db8::{id}/64' '1:2:3:4:5:6:7::{id_lo}/64' '1:2:3:4:5:6:{id}::/64' '::{id}/128' '{id}::/64' '{id}::1/64' '1:2:3:4:5:6:7:{id}/64'; do
    case "$template" in
    '1:2:3:4:5:6:7::{id_lo}/64') reject _identity_render "$template" 612 ipv6 ;;
    *) _identity_render "$template" 612 ipv6 >/dev/null ;;
    esac
  done
  for template in '1::2::{id}/64' '1:::2:{id}/64' ':1:2:3:4:5:6:{id}/64' '1:2:3:{id}/64' '1:2:3:4:5:6:7:{id}:9/64' '2001:db8::{id}/064' '2001:db8::{id}/129' '2001:db8::{id}/64/64'; do
    reject _identity_render "$template" 612 ipv6
  done
  ;;
defaults)
  cat <<'VARS' >"$TEST_DIR/default.vars"
var_ctid_min=100
var_ctid_max=199
var_net_template='192.0.2.{id}/24'
VARS
  load_vars_file "$TEST_DIR/default.vars"
  base_settings
  same 100 "$CT_ID"
  same 192.0.2.100/24 "$NET"
  cat <<'VARS' >"$TEST_DIR/bad.vars"
var_mac_template='02:00:00:00:{bad}:{id_lo2}'
VARS
  reject load_vars_file "$TEST_DIR/bad.vars"
  ;;
global-defaults)
  community_scripts_dir() { echo "$TEST_DIR"; }
  header_info() { :; }
  echo_default() { :; }
  cat <<'VARS' >"$TEST_DIR/default.vars"
var_ctid_min=150
var_ctid_max=199
var_net_template=192.0.2.{id}/24
var_net=dhcp
VARS
  default_var_settings >/dev/null
  same 150 "$CT_ID"
  same dhcp "$NET"
  unset var_net
  base_settings
  same 192.0.2.150/24 "$NET"
  ;;
env-precedence)
  cat <<'VARS' >"$TEST_DIR/app.vars"
var_ctid_min=610
var_mac=02:00:00:00:99:01
var_net=192.0.2.42/24
var_mac_template=02:00:00:00:{id_hi2}:{id_lo2}
var_net_template=10.20.{id_hi}.{id_lo}/16
VARS
  load_vars_file "$TEST_DIR/app.vars" yes
  base_settings
  same 612 "$CT_ID"
  same 02:00:00:00:99:09 "$MAC"
  same dhcp "$NET"
  ;;
precedence)
  # App defaults override global/app-script values; genuine exported env wins.
  policy
  cat <<'VARS' >"$TEST_DIR/app.vars"
var_ctid_min=610
var_mac_template=02:00:00:00:{id_hi2}:{id_lo2}
var_net_template=10.20.{id_hi}.{id_lo}/16
var_net=dhcp
var_mac=02:00:00:00:99:01
var_ipv6_template=2001:db8::{id}/64
var_ipv6_method=none
VARS
  load_vars_file "$TEST_DIR/app.vars" yes
  base_settings
  same 610 "$CT_ID"
  same 02:00:00:00:99:01 "$MAC"
  same dhcp "$NET"
  same none "$IPV6_METHOD"
  _IDENTITY_ENV_KEYS=' var_ctid_min var_mac var_net'
  var_ctid_min=612 var_mac=02:00:00:00:99:02 var_net=192.0.2.42/24
  load_vars_file "$TEST_DIR/app.vars" yes
  base_settings
  same 612 "$CT_ID"
  same 02:00:00:00:99:02 "$MAC"
  same 192.0.2.42/24 "$NET"
  ;;
save-reload)
  static_policy
  var_ctid=612
  base_settings
  var_vlan=6 VLAN=,tag=6
  saved=$(_build_current_app_vars_tmp)
  cp "$saved" "$TEST_DIR/saved.vars"
  rm -f "$saved"
  grep -Fqx 'var_mac_template=02:00:00:00:{id_hi2}:{id_lo2}' "$TEST_DIR/saved.vars"
  grep -Fqx 'var_net_template=10.20.{id_hi}.{id_lo}/16' "$TEST_DIR/saved.vars"
  grep -Fqx 'var_ipv6_template=2001:db8::{id_hi}:{id_lo}/64' "$TEST_DIR/saved.vars"
  if grep -Eq '^var_(mac|net|ipv6_static|ipv6_method)=' "$TEST_DIR/saved.vars"; then exit 1; fi
  unset var_ctid _IDENTITY_BOUND_ID _IDENTITY_GENERATED_MAC _IDENTITY_GENERATED_NET _IDENTITY_GENERATED_IPV6
  load_vars_file "$TEST_DIR/saved.vars" yes
  base_settings
  same 604 "$CT_ID"
  same 02:00:00:00:06:04 "$MAC"
  same 10.20.6.4/16 "$NET"
  same 2001:db8::6:4/64 "$IPV6_ADDR"
  same 6 "$VLAN"
  (net0_capture)
  grep -q -- ',ip6=2001:db8::6:4/64$' "$TEST_DIR/pct-options"
  ;;
save-ipv6-bounds | save-ipv6-mac | save-ipv6-all | save-ipv6-legacy)
  var_ctid=612
  case "$1" in
  save-ipv6-bounds) var_ctid_min=604 ;;
  save-ipv6-mac) var_mac_template='02:00:00:00:{id_hi2}:{id_lo2}' ;;
  save-ipv6-all) static_policy ;;
  save-ipv6-legacy) : ;;
  esac
  base_settings
  WIZARD_MAC="${MAC#*,hwaddr=}"
  WIZARD_NET=10.20.9.3/16 WIZARD_IPV6=2001:db8::93/64
  wizard_run
  same static "$IPV6_METHOD"
  same 2001:db8::93/64 "$IPV6_ADDR"
  saved=$(_build_current_app_vars_tmp)
  cp "$saved" "$TEST_DIR/saved.vars"
  rm -f "$saved"
  grep -Fqx 'var_ipv6_method=static' "$TEST_DIR/saved.vars"
  if [[ "$1" == save-ipv6-legacy ]]; then
    assert_lacks 'var_ipv6_static=' "$TEST_DIR/saved.vars"
  else
    grep -Fqx 'var_ipv6_static=2001:db8::93/64' "$TEST_DIR/saved.vars"
  fi
  case "$1" in
  save-ipv6-mac | save-ipv6-all) grep -Fqx 'var_mac_template=02:00:00:00:{id_hi2}:{id_lo2}' "$TEST_DIR/saved.vars" ;;
  esac
  if [[ "$1" == save-ipv6-all ]]; then
    grep -Fqx 'var_net_template=10.20.{id_hi}.{id_lo}/16' "$TEST_DIR/saved.vars"
    grep -Fqx 'var_ipv6_template=2001:db8::{id_hi}:{id_lo}/64' "$TEST_DIR/saved.vars"
  fi
  # Clear both config and rendered state; reload solely from the saved file.
  for key in ${!var_@} ${!_IDENTITY_@}; do unset "$key"; done
  var_ctid=614 var_os=debian var_version=13
  IPV6_ADDR=''
  load_vars_file "$TEST_DIR/saved.vars" yes
  base_settings
  same static "$IPV6_METHOD"
  same 614 "$CT_ID"
  same 10.20.9.3/16 "$NET"
  (net0_capture)
  if [[ "$1" == save-ipv6-legacy ]]; then
    same '' "${IPV6_ADDR:-}"
    assert_lacks ',ip6=' "$TEST_DIR/pct-options"
  else
    same 2001:db8::93/64 "$IPV6_ADDR"
    grep -q -- ',ip6=2001:db8::93/64$' "$TEST_DIR/pct-options"
  fi
  case "$1" in
  save-ipv6-mac | save-ipv6-all)
    same 02:00:00:00:06:14 "$MAC"
    grep -q -- ',hwaddr=02:00:00:00:06:14,' "$TEST_DIR/pct-options"
    ;;
  esac
  ;;
wizard | wizard-accept | wizard-id-change | wizard-clear-mac)
  static_policy
  var_ctid=612
  base_settings
  if [[ "$1" == wizard-id-change ]]; then
    WIZARD_ID=613
    reject wizard_run
    grep -q 'templates were rendered for CTID 612' "$TEST_DIR/rejected"
  else
    case "$1" in
    wizard-clear-mac)
      WIZARD_MAC=''
      WIZARD_NET=10.20.9.3/16 WIZARD_IPV6=2001:db8::93/64
      ;;
    wizard-accept)
      WIZARD_ACCEPT=1
      WIZARD_MAC="$MAC"
      WIZARD_NET="$NET" WIZARD_IPV6="$IPV6_ADDR"
      ;;
    *)
      WIZARD_MAC=02:00:00:00:99:03
      WIZARD_NET=10.20.9.3/16 WIZARD_IPV6=2001:db8::93/64
      ;;
    esac
    wizard_run
    same 612 "$CT_ID"
    same ",hwaddr=${WIZARD_MAC}" "${MAC:-,hwaddr=}"
    saved=$(_build_current_app_vars_tmp)
    cp "$saved" "$TEST_DIR/saved.vars"
    rm -f "$saved"
    unset var_mac var_net var_ipv6_static var_ipv6_method _IDENTITY_BOUND_ID
    load_vars_file "$TEST_DIR/saved.vars" yes
    base_settings
    same "$WIZARD_MAC" "$MAC"
    same "$WIZARD_NET" "$NET"
    same "$WIZARD_IPV6" "$IPV6_ADDR"
  fi
  ;;
ipv6-literal-implicit)
  var_ctid=612
  cat <<'VARS' >"$TEST_DIR/ipv6-literal.vars"
var_ctid_min=604
var_ipv6_template=2001:db8::{id}/64
var_ipv6_static=2001:db8::42/64
VARS
  load_vars_file "$TEST_DIR/ipv6-literal.vars" yes
  base_settings
  same static "$IPV6_METHOD"
  same 2001:db8::42/64 "$IPV6_ADDR"
  (net0_capture)
  grep -q -- ',ip6=2001:db8::42/64$' "$TEST_DIR/pct-options"
  ;;
ipv6-literal-methods)
  for method in static none auto dhcp disable; do
    (
      cat <<VARS >"$TEST_DIR/ipv6-method.vars"
var_ctid_min=604
var_ipv6_template=2001:db8::{id}/64
var_ipv6_static=2001:db8::42/64
var_ipv6_method=$method
VARS
      load_vars_file "$TEST_DIR/ipv6-method.vars" yes
      base_settings
      same "$method" "$IPV6_METHOD"
      (net0_capture)
      case "$method" in
      static) grep -q -- ',ip6=2001:db8::42/64$' "$TEST_DIR/pct-options" ;;
      auto | dhcp) grep -q -- ",ip6=$method$" "$TEST_DIR/pct-options" ;;
      none | disable) assert_lacks ',ip6=' "$TEST_DIR/pct-options" ;;
      esac
    )
  done
  ;;
wizard-back-edits | wizard-back-clear | wizard-modes | wizard-modes-static | wizard-cancel-ipv6)
  # Mode variants each drive real forward/back dialogs, then the actual builder.
  for method in auto dhcp none disable; do
    (
      static_policy
      var_ctid=612
      base_settings
      WIZARD_NAVIGATION="${1#wizard-}"
      WIZARD_IPV6_MODE="$method"
      rm -f "$TEST_DIR/dialogs" "$TEST_DIR/dialog-state"
      wizard_run
      if [[ "$WIZARD_NAVIGATION" == back-clear ]]; then same '' "$MAC"; fi
      if [[ "$WIZARD_NAVIGATION" == back-* ]]; then
        same 10.20.9.3/16 "$NET"
        same 2001:db8::93/64 "$IPV6_ADDR"
        grep -q '^STATIC IPv4 ADDRESS||10.20.9.3/16$' "$TEST_DIR/dialog-state"
        grep -q '^STATIC IPv6 ADDRESS||2001:db8::93/64$' "$TEST_DIR/dialog-state"
      else
        grep -q '^IPv4 CONFIGURATION|dhcp|' "$TEST_DIR/dialog-state"
        grep -q "^IPv6 CONFIGURATION|$method|" "$TEST_DIR/dialog-state"
      fi
      if [[ "$WIZARD_NAVIGATION" == back-clear ]]; then
        same '' "$MAC"
        grep -q '^MAC ADDRESS||$' "$TEST_DIR/dialog-state"
      else
        same ,hwaddr=02:00:00:00:99:03 "$MAC"
        grep -q '^MAC ADDRESS||02:00:00:00:99:03$' "$TEST_DIR/dialog-state"
      fi
      (net0_capture)
      case "$WIZARD_NAVIGATION" in
      back-*) grep -q -- ',ip=10.20.9.3/16,gw=10.20.0.1,tag=6,ip6=2001:db8::93/64' "$TEST_DIR/pct-options" ;;
      modes-static)
        same static "$IPV6_METHOD"
        same 10.20.9.3/16 "$NET"
        grep -q '^STATIC IPv4 ADDRESS||$' "$TEST_DIR/dialog-state"
        grep -q '^STATIC IPv6 ADDRESS||$' "$TEST_DIR/dialog-state"
        grep -q -- ',ip=10.20.9.3/16,gw=10.20.0.1,tag=6,ip6=2001:db8::93/64' "$TEST_DIR/pct-options"
        ;;
      modes | cancel-ipv6)
        same dhcp "$NET"
        same "$method" "$IPV6_METHOD"
        if [[ "$WIZARD_NAVIGATION" == cancel-ipv6 ]]; then
          same 2 "$(grep -c "^IPv6 CONFIGURATION|$method|" "$TEST_DIR/dialog-state")"
        fi
        case "$method" in
        auto | dhcp) grep -q -- ",ip=dhcp,tag=6,ip6=$method$" "$TEST_DIR/pct-options" ;;
        none | disable) assert_lacks ',ip6=' "$TEST_DIR/pct-options" ;;
        esac
        ;;
      esac
      if [[ "$WIZARD_NAVIGATION" == back-clear ]]; then
        assert_lacks ',hwaddr=' "$TEST_DIR/pct-options"
      else
        grep -q -- ',hwaddr=02:00:00:00:99:03,' "$TEST_DIR/pct-options"
      fi
    )
    # Back/edit scenarios are independent of nonstatic mode choices.
    if [[ "$1" == wizard-back-* ]]; then break; fi
  done
  ;;
final-net0)
  static_policy
  var_ctid=612 var_vlan=6
  base_settings
  (net0_capture)
  grep -q -- '-net0 name=eth0,bridge=vmbr0,hwaddr=02:00:00:00:06:12,ip=10.20.6.12/16,tag=6,ip6=2001:db8::6:12/64' "$TEST_DIR/pct-options"
  # Reservation-only path keeps DHCP and no static IPv6.
  unset var_net_template var_ipv6_template _IDENTITY_BOUND_ID
  base_settings
  (net0_capture)
  grep -q -- 'hwaddr=02:00:00:00:06:12,ip=dhcp,tag=6$' "$TEST_DIR/pct-options"
  ;;
late-collision)
  policy
  var_ctid=612
  base_settings
  backend
  pct() { echo 'unexpected pct invocation' >>"$TEST_DIR/pct-calls"; }
  reject get_valid_container_id 613
  reject _pct_create 613 ignored
  [[ ! -e "$TEST_DIR/pct-calls" ]]
  # Exercise real create_lxc_container's late collision branch before storage.
  CTID=612 PCT_OSTYPE=debian
  qm() { return 0; }
  msg_debug() { :; }
  reject create_lxc_container
  grep -q 'templates were rendered for CTID 612' "$TEST_DIR/rejected"
  [[ ! -e "$TEST_DIR/pct-calls" ]]
  ;;
pct-collision)
  policy
  var_ctid=612
  base_settings
  backend
  {
    echo 'collision_branch() {'
    awk '/  # First attempt \(PCT_OPTIONS/ {copy=1} copy && /^    else$/ {exit} copy {print}' "$CORE_DIR/pve/backend.func"
    echo 'fi; fi; }'
  } >"$TEST_DIR/collision-branch.sh"
  source "$TEST_DIR/collision-branch.sh"
  CTID=612 TEMPLATE_STORAGE=local TEMPLATE=fixture SESSION_ID=test
  LOGFILE="$TEST_DIR/pct.log" PCT_OPTIONS='-net0 name=eth0,hwaddr=02:00:00:00:06:12,ip=dhcp'
  msg_debug() { :; }
  pct() {
    echo "$*" >>"$TEST_DIR/pct-calls"
    echo 'VM 612 already exists'
    return 1
  }
  reject collision_branch
  same 1 "$(wc -l <"$TEST_DIR/pct-calls" | tr -d ' ')"
  grep -q '^create 612 ' "$TEST_DIR/pct-calls"
  grep -q 'templates were rendered for CTID 612' "$TEST_DIR/rejected"
  ;;
*)
  echo "Unknown scenario $1" >&2
  exit 1
  ;;
esac
