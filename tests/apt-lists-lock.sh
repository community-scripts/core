#!/usr/bin/env bash
# 22 runs on 15 hosts in a week: another apt held /var/lib/apt/lists/lock in the
# fresh container, the engine took that for a bad mirror and went through mirrors.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fn="$(awk '/_apt_update=.cs_apt_update[(][)] [{]/,/^    }.$/' "$CORE_DIR/pve/backend.func")"
fn="${fn#*"'"}"
fn="${fn%"'"}"
eval "$fn"

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

sleep() { echo s >>"$TEST_DIR/sleeps"; }
ps() {
  case "$*" in
  *"ppid= -p 377"*) echo "  320" ;;
  *"ppid= -p 320"*) echo "    1" ;;
  *"-p 377"*) echo "  377   320    42 apt-get update" ;;
  *"-p 320"*) echo "  320     1    43 /bin/sh /usr/local/bin/refresh" ;;
  esac
}
apt-get() {
  echo c >>"$TEST_DIR/calls"
  if (($(wc -l <"$TEST_DIR/calls") <= LOCKED)); then
    echo "E: Could not get lock /var/lib/apt/lists/lock. It is held by process 377 (apt-get)"
    echo "E: Unable to lock directory /var/lib/apt/lists/"
    return 100
  fi
  echo "$APT_SAYS"
  return "$APT_RC"
}
run() {
  LOCKED="$1" APT_RC="$2" APT_SAYS="$3"
  : >"$TEST_DIR/calls"
  : >"$TEST_DIR/sleeps"
  out="$(cs_apt_update 2>"$TEST_DIR/err")"
  rc=$?
  calls="$(wc -l <"$TEST_DIR/calls" | tr -d ' ')"
}

run 0 0 "Reading package lists..."
expect "a free lock: one update" "1 0" "$calls $rc"
expect "its output is passed on" "Reading package lists..." "$out"
expect "nothing is said about a lock" "" "$(cat "$TEST_DIR/err")"

run 2 0 "Reading package lists..."
expect "a held lock is waited for" "3 0" "$calls $rc"
expect "the waits are spaced" 2 "$(wc -l <"$TEST_DIR/sleeps" | tr -d ' ')"
expect "the holder is named once" 1 "$(grep -c 'apt-get update' "$TEST_DIR/err")"
expect "and what started it" 1 "$(grep -c '/usr/local/bin/refresh' "$TEST_DIR/err")"
expect "the lock error is not the result" 0 "$(grep -c 'Could not get lock' <<<"$out")"

run 99 0 ""
expect "a lock that stays ends the wait with its own code" "30 75" "$calls $rc"
expect "the lock error is the result then" 1 "$(grep -c 'Could not get lock' <<<"$out")"

run 0 100 "E: Failed to fetch http://deb.debian.org/debian/dists/trixie/InRelease"
expect "another failure is not retried" "1 100" "$calls $rc"

src="$CORE_DIR/pve/backend.func"
expect "the first attempt goes through the wait" 1 "$(grep -c 'cs_apt_update && apt-get install -y ${_base_pkgs}' "$src")"
expect "a lock that stayed skips the mirrors" 1 "$(grep -c '_apt_rc -eq 75' "$src")"
expect "the mirror loop waits too, on its security retry as well" 2 "$(grep -c 'APT_OUT=$(cs_apt_update)' "$src")"
expect "and stops on a lock" 1 "$(grep -A3 'APT_OUT=$(cs_apt_update)' "$src" | grep -c 'APT_RC -eq 75')"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
