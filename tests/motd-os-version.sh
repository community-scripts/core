#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/etc/profile.d" "$T/root"
relocate() { sed "s|/etc/|$T/etc/|g; s|/root/|$T/root/|g"; }
eval "$(awk '/^motd_ssh\(\) \{/,/^}/' "$CORE_DIR/lxc/install.func" | relocate)"
eval "$(awk '/^update_motd_ip\(\) \{/,/^}/' "$CORE_DIR/ui/validate.func" | relocate)"
eval "$(awk '/^on_exit\(\) \{/,/^}/' "$CORE_DIR/core/error_handler.func")"

PROFILE="$T/etc/profile.d/00_lxc-details.sh"
passed=0 failed=0

check() {
  if [[ "$3" == *"$2"* ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2> in <$3>" >&2
    failed=$((failed + 1))
  fi
}

os_release() { printf 'NAME="%s"\n%s' "$1" "${2:+VERSION_ID=\"$2\"$'\n'}" >"$T/etc/os-release"; }
get_current_ip() { echo 192.0.2.10; }
post_progress_to_api() { :; }
_is_container_context() { return 0; }
# shellcheck disable=SC2034
TAB="" NETWORK="" YW="" GN="" CL="" OS="" HOSTNAME="" INFO="" GATEWAY="" BOLD="" RD="" OS_TYPE=debian OS_VERSION=12

shells=()
for sh in bash dash "busybox sh"; do
  command -v "${sh%% *}" >/dev/null 2>&1 && $sh -c : 2>/dev/null && shells+=("$sh")
done

os_release "Debian GNU/Linux" 12
APPLICATION=Test motd_ssh
os_release "Debian GNU/Linux" 13
for sh in "${shells[@]}"; do
  check "$sh: login shows the upgraded release" "OS: Debian GNU/Linux - Version: 13" "$($sh -c ". '$PROFILE'" 2>&1)"
  check "$sh: NAME stays out of the login shell" "unset" "$($sh -c ". '$PROFILE' >/dev/null 2>&1; echo \${NAME-unset}")"
done

os_release "Arch Linux"
check "no VERSION_ID reads as rolling" "Arch Linux - Version: rolling" "$(bash -c ". '$PROFILE'")"
rm -f "$T/etc/os-release"
check "no os-release still prints a line" "OS: Linux - Version: rolling" "$(bash -c ". '$PROFILE'")"
check "/etc/motd carries no version" "none" "$(grep -q 'Version' "$T/etc/motd" && echo found || echo none)"

esc=$'\033'
cat >"$PROFILE" <<EOF
echo -e "${esc}[1mTest LXC Container${esc}[m"
echo -e "    community-scripts"
echo -e "    ${esc}[33m OS: ${esc}[1;92mDebian GNU/Linux - Version: 12${esc}[m"
echo -e "    ${esc}[33m IP Address: ${esc}[1;92m\$(echo 192.0.2.10)${esc}[m"
EOF
printf '\nTest LXC Container\n OS: Debian GNU/Linux - Version: 12\n\n' >"$T/etc/motd"
os_release "Debian GNU/Linux" 13
update_motd_ip >/dev/null 2>&1
check "update turns a fixed OS line into one read at login" "Debian GNU/Linux - Version: 13" "$(bash -c ". '$PROFILE'")"
check "update drops the fixed OS line from /etc/motd" "none" "$(grep -q 'Version' "$T/etc/motd" && echo found || echo none)"
cp "$PROFILE" "$T/before"
update_motd_ip >/dev/null 2>&1
check "a second update leaves the OS line alone" "same" "$(cmp -s "$PROFILE" "$T/before" && echo same || echo changed)"

result=$(
  cleanup_lxc() { :; }
  update_motd_ip() { echo motd; }
  _CS_UPDATE_CLEANUP=1
  trap on_exit EXIT
  exit 0
)
check "an update that exits inside update_script still refreshes the MOTD" "motd" "$result"

printf '%s passed, %s failed (shells: %s)\n' "$passed" "$failed" "${shells[*]}"
((failed == 0))
