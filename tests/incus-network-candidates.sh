#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for fn in _incus_bridge_members _incus_bridge_uplink incus_default_profile_network incus_network_candidates; do
  eval "$(awk "/^${fn}[(][)] [{]/,/^}/" "$CORE_DIR/incus/core.func")"
done
eval "$(awk '/^populate_advanced_bridge_menu[(][)] [{]/,/^}/' "$CORE_DIR/incus/build.func")"

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

declare -A SHOW STATE
NETS=() PROFILE=""

# net <name> <type> <managed> <nat> [instance...]
net() {
  local n="$1" type="$2" managed="$3" nat="$4" i
  shift 4
  NETS+=("$n")
  SHOW[$n]=$(
    printf 'config:\n'
    [[ "$nat" == yes ]] && printf '  ipv4.nat: "true"\n'
    printf 'description: ""\nname: %s\ntype: %s\nused_by:\n' "$n" "$type"
    for i in "$@"; do printf -- '- /1.0/instances/%s\n' "$i"; done
    printf -- '- /1.0/profiles/default\nmanaged: %s\nstatus: Created\n' "$managed"
  )
}

# bridge_state <name> <members...>; no members gives null, "[]" an empty list
bridge_state() {
  local n="$1" m list
  shift
  if (($# == 0)); then
    list='null'
  elif [[ "$1" == "[]" ]]; then
    list='[]'
  else
    list=$(printf '[\n'; for m in "$@"; do printf '\t\t\t"%s",\n' "$m"; done | sed '$ s/,$//'; printf '\t\t]')
  fi
  STATE[$n]=$(printf '{\n\t"addresses": [],\n\t"bridge": {\n\t\t"forward_delay": 1500,\n\t\t"id": "8000.0",\n\t\t"stp": false,\n\t\t"upper_devices": %s,\n\t\t"vlan_default": 1\n\t},\n\t"type": "broadcast"\n}' "$list")
}
nic_state() { STATE[$1]=$(printf '{\n\t"addresses": [],\n\t"bridge": null,\n\t"type": "broadcast"\n}'); }

incus() {
  case "$1" in
  network)
    case "$2" in
    list) for n in "${NETS[@]}"; do echo "$n,x,YES"; done ;;
    show) printf '%s\n' "${SHOW[$3]}" ;;
    esac
    ;;
  profile) printf '%s\n' "$PROFILE" ;;
  query)
    local n="${2#/1.0/networks/}"
    n="${n%/state}"
    [[ -n "${STATE[$n]:-}" ]] || return 1
    printf '%s\n' "${STATE[$n]}"
    ;;
  esac
}

reset() {
  NETS=() PROFILE=""
  SHOW=() STATE=()
}

profile_on() { PROFILE=$(printf 'devices:\n  eth0:\n    name: eth0\n    network: %s\n    type: nic\nname: default\n' "$1"); }

# tai8pan's IncusOS host (community-scripts/Incus#559): eno1 is the managed
# physical network on the bridge IncusOS builds for the instances role.
reset
net eno1 physical true no
bridge_state eno1 enp3s0
net icompose0 bridge true yes c1
net incusbr0 bridge true yes v1
net ixui-default bridge true yes c2
net meshbr0 bridge true no
SHOW[meshbr0]=${SHOW[meshbr0]/config:/config:$'\n'  ipv6.nat: \"true\"}
profile_on incusbr0
expect "a managed physical network on a bridge is offered first" "eno1 icompose0 incusbr0 ixui-default meshbr0" "$(incus_network_candidates | paste -sd' ')"

reset
net enp1s0 physical false no
nic_state enp1s0
net uplink0 physical true no
nic_state uplink0
net incusbr0 bridge true yes
expect "a bare NIC is never offered, managed or not" "incusbr0" "$(incus_network_candidates | paste -sd' ')"

reset
net incusbr0 bridge true yes a b c
net br0 bridge false no
bridge_state br0 eno1 veth1
expect "instances on a NAT bridge do not outrank a LAN bridge" "br0 incusbr0" "$(incus_network_candidates | paste -sd' ')"

reset
net incusbr0 bridge true yes a b c
net lan0 bridge true no
net lan1 bridge true no d
expect "class decides first, instances within a class" "lan1 lan0 incusbr0" "$(incus_network_candidates | paste -sd' ')"

reset
net docker0 bridge false no
bridge_state docker0 veth1 veth2
net br20 bridge false no
bridge_state br20 veth9 vlan20 vnet0
net br9 bridge false no
bridge_state br9 "[]"
net br8 bridge false no
bridge_state br8
expect "uplink is the first member that is not a guest" "vlan20" "$(_incus_bridge_uplink br20)"
expect "a bridge of guests only has no uplink" 1 "$(_incus_bridge_uplink docker0 >/dev/null; echo $?)"
expect "an empty member list is no uplink" 1 "$(_incus_bridge_uplink br9 >/dev/null; echo $?)"
expect "a null member list is no uplink" 1 "$(_incus_bridge_uplink br8 >/dev/null; echo $?)"
expect "members are read from the server" "veth9 vlan20 vnet0" "$(_incus_bridge_members br20 | paste -sd' ')"
expect "only the bridge with an uplink is offered" "br20" "$(incus_network_candidates | paste -sd' ')"

reset
net br0 bridge false no a b
bridge_state br0 eno2
net eno1 physical true no
bridge_state eno1 enp3s0
profile_on eno1
expect "the default profile's physical network goes first" "eno1 br0" "$(incus_network_candidates | paste -sd' ')"

reset
net eno1 physical true no
bridge_state eno1 enp3s0
net uplink0 physical true no
nic_state uplink0
net incusbr0 bridge true yes
populate_advanced_bridge_menu
expect "the wizard lists the bridged physical network, not the bare one" "eno1|LAN bridge (uplink: enp3s0)|incusbr0|NAT - not reachable from your LAN" "$(IFS='|'; echo "${BRIDGE_MENU_OPTIONS[*]}")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
