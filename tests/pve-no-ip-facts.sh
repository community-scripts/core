#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

eval "$(awk '/^_pve_no_ip_facts[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func" |
  sed "s#/sys/class/net#$TEST_DIR/net#g")"

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

msg_warn() { echo "$1"; }
NET0="" LINK="UP"
pct() {
  case "$1" in
  config) echo "arch: amd64" && echo "net0: $NET0" ;;
  exec) [[ -n "$LINK" ]] && echo "eth0@if12 $LINK aa:bb:cc:dd:ee:ff <BROADCAST,UP>" ;;
  esac
}
bridge() {
  rm -rf "$TEST_DIR/net"
  [[ "$1" == "none" ]] && return 0
  mkdir -p "$TEST_DIR/net/vmbr0"
  [[ "$1" == "ovs" ]] && return 0
  mkdir -p "$TEST_DIR/net/vmbr0/brif"
  local p
  for p in "${@:2}"; do : >"$TEST_DIR/net/vmbr0/brif/$p"; done
}

NET0="name=eth0,bridge=vmbr0,hwaddr=BC:24:11:00:00:01,ip=dhcp,tag=20,type=veth"
bridge linux veth101i0 fwpr101p0
out="$(_pve_no_ip_facts 101 vmbr0)"
check "DHCP on a bridge without an uplink" \
  "Container network: ip=dhcp, VLAN 20, eth0 UP|Bridge vmbr0 has no uplink port, so nothing outside this host can answer on it|No DHCP server answered on vmbr0 (VLAN 20)" \
  "$(paste -sd'|' <<<"$out")"
check "the MAC address stays out of the log" 0 "$(grep -ci 'BC:24' <<<"$out" || true)"

bridge linux veth101i0 enp3s0
check "DHCP with an uplink blames the DHCP server only" \
  "Container network: ip=dhcp, VLAN 20, eth0 UP|No DHCP server answered on vmbr0 (VLAN 20)" \
  "$(_pve_no_ip_facts 101 vmbr0 | paste -sd'|')"

NET0="name=eth0,bridge=vmbr0,ip=192.168.1.50/24,gw=192.168.1.1,type=veth"
LINK=""
check "a static address with eth0 missing" "Container network: ip=192.168.1.50/24, eth0 missing" \
  "$(_pve_no_ip_facts 101 vmbr0 | paste -sd'|')"

LINK="DOWN"
bridge none
check "a bridge that is not there" "Container network: ip=192.168.1.50/24, eth0 DOWN|Bridge vmbr0 does not exist on this host" \
  "$(_pve_no_ip_facts 101 vmbr0 | paste -sd'|')"

bridge ovs
check "an Open vSwitch bridge has no brif and is not judged" "Container network: ip=192.168.1.50/24, eth0 DOWN" \
  "$(_pve_no_ip_facts 101 vmbr0 | paste -sd'|')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
