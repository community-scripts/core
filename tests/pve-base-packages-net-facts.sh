#!/usr/bin/env bash
# 51 Alpine and about 15 Debian runs a week ended in "base packages failed" for
# a container that had no way out; the message did not say so and the run was
# filed as a general or an apt error.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_pve_ct_net_facts[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"

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

YW=""
msg_warn() { echo "WARN $*" >>"$TEST_DIR/out"; }
msg_custom() { echo "INFO $3" >>"$TEST_DIR/out"; }
pct() {
  shift 3
  case "$1" in
  ip) [[ -z "$GW" ]] || echo "default via $GW dev eth0" ;;
  awk) echo "$DNS " ;;
  ping) [[ "${*: -1}" == "$GW" ]] && return "$GW_RC" || return "$OUT_RC" ;;
  ping6 | sh) return "$OUT_RC" ;;
  getent) echo "${*: -1}" >>"$TEST_DIR/asked"; return "$DNS_RC" ;;
  esac
}
facts() {
  : >"$TEST_DIR/out"
  : >"$TEST_DIR/asked"
  CTID=100 _pve_ct_net_facts "$TEST_DIR/log"
  rc=$?
}
: >"$TEST_DIR/log"

GW=192.168.1.1 DNS="192.168.1.1 1.1.1.1" GW_RC=0 OUT_RC=0 DNS_RC=0 var_os=debian
facts
expect "a container that reaches everything: no code of its own" 0 "$rc"
expect "gateway and resolvers are named" "WARN Container network: gateway 192.168.1.1, DNS 192.168.1.1 1.1.1.1" "$(cat "$TEST_DIR/out")"
expect "debian asks for its mirror" deb.debian.org "$(cat "$TEST_DIR/asked")"

OUT_RC=1
facts
expect "no connection out is a connect failure" 7 "$rc"
expect "and is said" 1 "$(grep -c 'has no connection out' "$TEST_DIR/out")"
expect "names are not asked for then" "" "$(cat "$TEST_DIR/asked")"

GW_RC=1
facts
expect "a silent gateway is named" 1 "$(grep -c 'gateway 192.168.1.1 does not answer' "$TEST_DIR/out")"

GW_RC=0 OUT_RC=0 DNS_RC=2 var_os=alpine
facts
expect "names that do not resolve are a DNS failure" 6 "$rc"
expect "alpine asks for its own mirror" dl-cdn.alpinelinux.org "$(cat "$TEST_DIR/asked")"

GW="" DNS="" OUT_RC=1
facts
expect "no route and no resolver read as none" 1 "$(grep -c 'gateway none, DNS none' "$TEST_DIR/out")"

cat >"$TEST_DIR/log" <<'LOG'
WARNING: updating and opening https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/APKINDEX.tar.gz: DNS: transient error (try again later)
ERROR: unable to select packages:
  bash (no such package):
LOG
facts
expect "apk's fetch error is the reason, not what follows from it" 1 "$(grep -c 'INFO WARNING: updating and opening .*DNS: transient error' "$TEST_DIR/out")"
cat >"$TEST_DIR/log" <<'LOG'
Err:2 http://security.debian.org trixie-security InRelease
E: Failed to fetch http://deb.debian.org/debian/dists/trixie/InRelease  Temporary failure resolving 'deb.debian.org'
E: Some index files failed to download.
LOG
facts
expect "apt's fetch error too" 1 "$(grep -c "INFO E: Failed to fetch .*Temporary failure resolving" "$TEST_DIR/out")"

src="$CORE_DIR/pve/backend.func"
expect "the Alpine failure reports them and takes their code, else 100" 1 "$(grep -B1 'msg_error "Failed to install base packages in Alpine container"' "$src" | grep -c '_pve_ct_net_facts "$BUILD_LOG" && install_exit_code=100 || install_exit_code=$?')"
expect "a container without a way out is not asked for a mirror" 1 "$(grep -B4 'mirror_exit -eq 2 ]] && { : >/dev/tty; }' "$src" | grep -c '_pve_ct_net_facts "$BUILD_LOG" || _net_rc=$?; ((_net_rc))')"
expect "and ends with the network code" 1 "$(grep -c 'install_exit_code=$_net_rc' "$src")"
expect "without a terminal nobody is asked either" 1 "$(grep -c 'mirror_exit -eq 2 ]] && { : >/dev/tty; } 2>/dev/null; then' "$src")"

expect "a container that still resolves nothing ends before apt runs" 1 "$(grep -c 'install_exit_code -ne 0 ]] || _cs_shield_hangup pct exec "$CTID" -- bash -c "${_apt_update}' "$src")"
expect "unless a proxy or an apt cache does the resolving" 1 "$(grep -c 'z "${HTTP_PROXY:-}" && "${APT_CACHER:-}" != "yes" ]] && ! pct exec "$CTID" -- getent hosts deb.debian.org' "$src")"

# A container without a gateway was offered "Retry with DNS override", which
# rebuilt it and failed the same way.
for f in pve/backend.func incus/backend.func; do
  expect "$f offers no DNS retry without a connection out" 1 \
    "$(grep -B2 'Retry with DNS override in LXC' "$CORE_DIR/$f" | grep -c 'is_network_issue" == true && $install_exit_code -ne 7 ]]')"
done
echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
