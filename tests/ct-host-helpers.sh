#!/usr/bin/env bash
# ct scripts called pct after build_container (authentik, urbackupserver,
# dietpi), which does not exist on an Incus host. Both backends now define the
# same host-side helpers.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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
load() { eval "$(awk '/^ct_(exec|restart|exec_hint|attach_volume)[(][)] [{]/,/^}/' "$CORE_DIR/$1")"; }
calls() { paste -sd'|' "$TEST_DIR/calls"; }
msg_error() { echo "error: $*" >>"$TEST_DIR/calls"; }
sleep() { :; }

for f in pve/backend.func incus/build.func; do
  expect "$f defines all four" 4 "$(grep -cE '^ct_(exec|restart|exec_hint|attach_volume)[(][)] [{]' "$CORE_DIR/$f")"
done

# --- Proxmox ---
load pve/backend.func
CTID=123 CONTAINER_STORAGE=local-lvm BUILD_LOG="$TEST_DIR/log" MP_TAKEN="" SET_RC=0
pct() {
  case "$1" in
  config) printf '%s\n' "rootfs: local-lvm:vm-123-disk-0,size=4G" $MP_TAKEN; return 0 ;;
  status) echo "status: running"; return 0 ;;
  set) echo "pct $*" >>"$TEST_DIR/calls"; [[ "$3" == --protection ]] || return "$SET_RC" ;;
  *) echo "pct $*" >>"$TEST_DIR/calls" ;;
  esac
}

: >"$TEST_DIR/calls"; ct_exec systemctl enable -q --now app
expect "pve: ct_exec" "pct exec 123 -- systemctl enable -q --now app" "$(calls)"
: >"$TEST_DIR/calls"; ct_restart
expect "pve: ct_restart" "pct reboot 123" "$(calls)"
expect "pve: ct_exec_hint" "pct exec 123 -- runuser -u orb -- orb link" "$(ct_exec_hint runuser -u orb -- orb link)"

: >"$TEST_DIR/calls"; ct_attach_volume 1 /opt/authentik-data
expect "pve: a volume is attached with the container stopped" \
  "0 pct stop 123|pct set 123 -mp0 local-lvm:1,mp=/opt/authentik-data,backup=1|pct start 123" "$? $(calls)"

: >"$TEST_DIR/calls"; PROTECT_CT=yes MP_TAKEN="mp0: local-lvm:vm-123-disk-1,mp=/data" ct_attach_volume 8 /srv
expect "pve: protection is lifted for it, and a taken mp0 is skipped" \
  "pct stop 123|pct set 123 --protection 0|pct set 123 -mp1 local-lvm:8,mp=/srv,backup=1|pct set 123 --protection 1|pct start 123" "$(calls)"

: >"$TEST_DIR/calls"; SET_RC=1 ct_attach_volume 1 /opt/x
expect "pve: a refused volume fails, with the container started again" \
  "1 pct stop 123|pct set 123 -mp0 local-lvm:1,mp=/opt/x,backup=1|pct start 123|error: Could not attach a 1 GB volume at /opt/x (see the log)" "$? $(calls)"

# --- Incus ---
load incus/build.func
CT_NAME=web CONTAINER_STORAGE=tank ADD_RC=0
incus_ct_exec() { echo "exec $*" >>"$TEST_DIR/calls"; }
incus() { echo "incus $*" >>"$TEST_DIR/calls"; [[ "${*:1:3}" == "config device add" ]] && return "$ADD_RC"; return 0; }

: >"$TEST_DIR/calls"; ct_exec systemctl enable -q --now app
expect "incus: ct_exec" "exec systemctl enable -q --now app" "$(calls)"
: >"$TEST_DIR/calls"; ct_restart
expect "incus: ct_restart" "incus restart web" "$(calls)"
expect "incus: ct_exec_hint" "incus exec web -- runuser -u orb -- orb link" "$(ct_exec_hint runuser -u orb -- orb link)"

: >"$TEST_DIR/calls"; ct_attach_volume 1 /opt/authentik-data
expect "incus: a custom volume on the container's pool, added while it runs" \
  "0 incus storage volume create tank web-authentik-data size=1GiB|incus config device add web authentik-data disk pool=tank source=web-authentik-data path=/opt/authentik-data" "$? $(calls)"

: >"$TEST_DIR/calls"; ADD_RC=1 ct_attach_volume 1 /opt/x
expect "incus: a refused volume fails" 1 "$?"

echo "passed=${passed} failed=${failed}"
((failed == 0))
