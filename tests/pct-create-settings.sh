#!/usr/bin/env bash
# Settings that reached pct create and were rejected there: DNS servers or
# search domains separated by spaces (the wizard asks for that), tags with
# spaces, an ID with a leading zero, cores that are not a number.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(_cs_pct_list|validate_ct_settings)[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"
eval "$(awk '/^(validate_hostname|validate_ipv6_address|validate_ip_address|validate_gateway_ip|validate_ram_size|validate_nameservers|validate_searchdomain|validate_mount_fs)[(][)] [{]/,/^}/' "$CORE_DIR/ui/validate.func")"

passed=0 failed=0
TAB="  " YW=""
msg_error() { echo "$*"; }
msg_custom() { :; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

expect "DNS servers separated by spaces become one argument" "1.1.1.1,9.9.9.9" "$(_cs_pct_list , "1.1.1.1 9.9.9.9")"
expect "mixed separators and stray spaces are folded" "1.1.1.1,9.9.9.9,8.8.8.8" "$(_cs_pct_list , " 1.1.1.1, 9.9.9.9;8.8.8.8 ")"
expect "tags with spaces stay one argument" "community-script;docker;media" "$(_cs_pct_list ';' "community-script;docker, media")"
set -- -nameserver=$(_cs_pct_list , "1.1.1.1 9.9.9.9")
expect "the unquoted expansion yields a single word" 1 "$#"
expect "an empty list stays empty" "" "$(_cs_pct_list , "  ")"

valid() {
  CTID=105 CORE_COUNT=2 DISK_SIZE=8 RAM_SIZE=2048 PW="" NET=dhcp GATE="" ALLOW_MOUNT_FS=""
  NS="-nameserver=1.1.1.1 9.9.9.9" SD="-searchdomain=home.lan"
}

valid
out="$(validate_ct_settings)"
expect "valid settings pass" 0 "$?"

valid
CTID=02057
out="$(validate_ct_settings)"
expect "an ID with a leading zero is refused before pct create" 208 "$?"
expect "and named" 1 "$(grep -c "container ID '02057'" <<<"$out")"

valid
CORE_COUNT=a
out="$(validate_ct_settings)"
expect "cores that are not a number are refused" 208 "$?"
expect "and named" 1 "$(grep -c "CPU cores 'a'" <<<"$out")"

validate_hostname "frigate."
expect "a hostname with a trailing dot is invalid" 1 "$?"
validate_hostname "frigate.home.lan"
expect "an FQDN is still valid" 0 "$?"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
