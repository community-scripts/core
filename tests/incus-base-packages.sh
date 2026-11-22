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

echo "passed=${passed} failed=${failed}"
((failed == 0))
