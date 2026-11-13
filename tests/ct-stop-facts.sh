#!/usr/bin/env bash
# 55 runs in a week ended in "Container stopped by itself during its setup"
# with nothing but the host unit's start and stop in the log.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$CORE_DIR/pve/backend.func"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
eval "$(awk '/^_pve_ct_stop_facts[(][)] [{]/,/^}/' "$BACKEND" | sed "s#/var/lib/lxc#$TEST_DIR/lxc#g")"
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

TAB="  " CTID=101 _CS_INSTALL_STARTED=1793658000
ROOT="$TEST_DIR/lxc/101/rootfs"
MOUNT_OK=1
pct() {
  echo "$1" >>"$TEST_DIR/pct.calls"
  [[ "$1" != mount ]] || ((MOUNT_OK))
}
journalctl() {
  case " $* " in
  *" -k "*) cat "$TEST_DIR/kernel" ;;
  *" -D $ROOT/var/log/journal "*) cat "$TEST_DIR/ctjournal" ;;
  *) return 1 ;;
  esac
}
reset() {
  rm -rf "$TEST_DIR/lxc" "$TEST_DIR/pct.calls"
  mkdir -p "$ROOT/var/log"
  : >"$TEST_DIR/kernel"
  : >"$TEST_DIR/ctjournal"
}

reset
mkdir -p "$ROOT/var/log/journal"
for i in $(seq 1 20); do echo "[ 0.$i] systemd[1]: Started unit$i.service." >>"$TEST_DIR/ctjournal"; done
echo "[ 2.1] systemd[1]: Received SIGRTMIN+4 from PID 1 (systemd)." >>"$TEST_DIR/ctjournal"
for i in $(seq 1 20); do echo "[ 2.$((i + 1))] systemd[1]: Stopped unit$i.service." >>"$TEST_DIR/ctjournal"; done
printf '%s\n' \
  'audit: type=1400 apparmor="DENIED" operation="mount" profile="lxc-101_</var/lib/lxc>" name="/run/"' \
  'audit: type=1400 apparmor="DENIED" operation="mount" profile="lxc-1010_</var/lib/lxc>" name="/run/"' \
  'oom-kill:constraint=CONSTRAINT_MEMCG,task_memcg=/lxc/101/ns/system.slice,task=node' \
  'oom-kill:constraint=CONSTRAINT_MEMCG,task_memcg=/lxc/1010/ns/system.slice,task=java' >"$TEST_DIR/kernel"
out="$(_pve_ct_stop_facts)"
expect "kernel lines about this container only" 2 "$(grep -c '^  kernel: ' <<<"$out")"
expect "no kernel line about container 1010" 0 "$(grep -c '1010' <<<"$out" || true)"
expect "the log starts three entries before the shutdown signal" "Started unit18.service." \
  "$(grep -A1 'shutdown began' <<<"$out" | tail -n1 | awk '{print $(NF-1), $NF}')"
expect "the shutdown signal is shown" 1 "$(grep -c 'Received SIGRTMIN+4' <<<"$out")"
expect "twelve log lines at most" 12 "$(grep -c '^    \[' <<<"$out")"
expect "the rootfs is unmounted again" "mount unmount" "$(paste -sd' ' "$TEST_DIR/pct.calls")"

reset
for i in $(seq 1 30); do echo "Nov 11 10:48:0$((i % 10)) ct kernel: line $i" >>"$ROOT/var/log/syslog"; done
out="$(_pve_ct_stop_facts)"
expect "without a journal, the tail of syslog" "line 30" "$(tail -n1 <<<"$out" | awk '{print $(NF-1), $NF}')"
expect "twelve syslog lines without a shutdown marker" 12 "$(grep -c 'kernel: line' <<<"$out")"

reset
mkdir -p "$ROOT/var/log/journal"
echo "[ 0.1] systemd[1]: Started x.service." >"$TEST_DIR/ctjournal"
MOUNT_OK=0
out="$(_pve_ct_stop_facts)"
expect "a rootfs that will not mount is left alone" "mount" "$(paste -sd' ' "$TEST_DIR/pct.calls")"
expect "and nothing is printed for it" "" "$out"
MOUNT_OK=1

reset
rc="$(
  set -eEo pipefail
  trap 'echo ERR' ERR
  _pve_ct_stop_facts >/dev/null
  echo "rc=$?"
)"
expect "an empty kernel log and no container log trip neither errexit nor the ERR trap" "rc=0" "$rc"

expect "both stopped-by-itself paths collect the facts" 2 \
  "$(awk '/^(_pve_ct_gone_during_setup|_pve_wait_for_detached_install)[(][)] [{]/,/^}/' "$BACKEND" | grep -c '^ *_pve_ct_stop_facts$')"
expect "the setup clock starts with the container" 1 \
  "$(grep -A2 'msg_info "Starting container"' "$BACKEND" | grep -c '_CS_INSTALL_STARTED="$(date +%s)"')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
