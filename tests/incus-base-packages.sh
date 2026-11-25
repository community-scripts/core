#!/usr/bin/env bash
# FreeScout died on Incus at `systemctl enable --now cron`: a Proxmox template
# ships cron, python3, xz-utils and more, the linuxcontainers.org images do not.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^incus_customize_container[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
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

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
sleep() { :; }
timedatectl() { echo UTC; }
incus_set_root_password() { :; }
_cs_host_arch() { echo "${MOCK_ARCH:-amd64}"; }
incus_ct_exec() { echo "$*" >>"$TEST_DIR/exec"; }

installed() {
  : >"$TEST_DIR/exec"
  var_os="$1" timezone=UTC incus_customize_container
  grep -o 'apt-get install -y [^>]*' "$TEST_DIR/exec" | tail -n1
}

line="$(installed debian)"
for pkg in sudo curl jq cron logrotate wget xz-utils bzip2 file less nano whiptail python3 perl lsof cpio; do
  expect "debian gets $pkg" 1 "$(grep -cw -- "$pkg" <<<"$line")"
done
expect "ubuntu gets the same set" "$line" "$(installed ubuntu)"
expect "devuan too" "$line" "$(installed devuan)"
expect "alpine keeps its own packages" 0 "$(var_os=alpine; : >"$TEST_DIR/exec"; incus_customize_container; grep -c 'apt-get' "$TEST_DIR/exec")"

# A failed install used to say "apt-get base packages installation failed" and
# nothing else: apt's output went to /dev/null.
eval "$(awk '/^_incus_ct_net_facts[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"
msg_error() { echo "error: $*"; }
msg_warn() { echo "warn: $*"; }
msg_custom() { echo "info: $3"; }
YW=""
incus_ct_exec() {
  case "$*" in
  *apt-get*) echo "E: Failed to fetch http://deb.debian.org/debian/dists/trixie/InRelease  Temporary failure resolving 'deb.debian.org'"; return 100 ;;
  "ip -4 route"*) echo "default via 10.0.0.1 dev eth0" ;;
  awk*) printf '8.8.8.8 1.1.1.1 ' ;;
  ping*) return "${GW_RC:-0}" ;;
  timeout*) return "${TCP_RC:-0}" ;;
  getent*|*getent*) return "${DNS_RC:-0}" ;;
  esac
}
fail() { BUILD_LOG="$TEST_DIR/build.log"; : >"$BUILD_LOG"; (var_os=debian timezone=UTC incus_customize_container) 2>&1; echo "exit=$?"; }

out="$(DNS_RC=2 fail)"
expect "a failed install still ends with 100" "exit=100" "$(tail -n 1 <<<"$out")"
expect "apt's output is in the log" 1 "$(grep -c "Temporary failure resolving" "$TEST_DIR/build.log" | awk '{print ($1 > 0)}')"
expect "and its last error in the message" 1 "$(grep -c "info: apt: E: Failed to fetch .*Temporary failure resolving 'deb.debian.org'" <<<"$out")"
expect "with the container's gateway and DNS" 1 "$(grep -c 'warn: Container network: gateway 10.0.0.1, DNS 8.8.8.8 1.1.1.1' <<<"$out")"
expect "a resolver that does not answer is named" 1 "$(grep -c 'warn: The container reaches the internet but resolves no names' <<<"$out")"
out="$(TCP_RC=1 GW_RC=1 fail)"
expect "so is a dead gateway" 1 "$(grep -c 'warn: The gateway 10.0.0.1 does not answer the container' <<<"$out")"
expect "and no way out" 1 "$(grep -c 'warn: The container has no connection out' <<<"$out")"

echo "passed=${passed} failed=${failed}"
((failed == 0))
