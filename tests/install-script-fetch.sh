#!/usr/bin/env bash
# 26 runs a week failed on install/<app>-install.sh only after their container
# stood ready, all with a fork hint: retired scripts (dockge, dokploy), forks,
# and network errors whose reason never reached the log.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$CORE_DIR/pve/backend.func"
eval "$(awk '/^_cs_shield_hangup[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^_pve_fetch_install_script[(][)] [{]/,/^}/' "$BACKEND")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
MSG="$TEST_DIR/msg"
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

msg_error() { echo "ERROR $1" >>"$MSG"; }
msg_custom() { echo "$3" >>"$MSG"; }
YW="" APP="Dockge" NSAPP="dockge" var_install="dockge-install"
COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
unset COMMUNITY_SCRIPTS_ROOT

fetch() {
  : >"$MSG"
  _install_script="stale"
  _pve_fetch_install_script
  echo "rc=$?"
}

_cs_fetch_text() { printf '#!/usr/bin/env bash\necho installing\n'; }
expect "a fetched script is kept" "rc=0" "$(fetch)"
fetch >/dev/null
expect "with its content" "echo installing" "$(tail -n1 <<<"$_install_script")"

_cs_fetch_text() { echo "curl: (22) The requested URL returned error: 404" >&2; return 22; }
expect "a missing script stops with 115" "rc=115" "$(fetch)"
fetch >/dev/null
expect "it says where it was not found" "ERROR install/dockge-install.sh is not in https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main" "$(head -n1 "$MSG")"
expect "it names a retired script as one cause" 1 "$(grep -c 'retired or became an addon' "$MSG")"
expect "and a fork as the other" 1 "$(grep -c 'Running a fork' "$MSG")"
expect "nothing is left to run" "" "$_install_script"

_cs_fetch_text() { echo "curl: (6) Could not resolve host: raw.githubusercontent.com" >&2; return 6; }
fetch >/dev/null
expect "a network failure says so" "ERROR Could not fetch install/dockge-install.sh from https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main" "$(head -n1 "$MSG")"
expect "with curl's reason" "curl: (6) Could not resolve host: raw.githubusercontent.com" "$(sed -n 2p "$MSG")"
expect "and no fork hint" 0 "$(grep -c 'fork' "$MSG" || true)"

_cs_fetch_text() { printf '#!/usr/bin/env bash\napt-get ins'; echo "curl: (18) transfer closed with 1024 bytes remaining" >&2; return 18; }
fetch >/dev/null
expect "a cut-off script is never run" "" "$_install_script"

_cs_fetch_text() { return 0; }
expect "an empty answer counts as missing" "rc=115" "$(fetch)"

rc="$(
  set -eEo pipefail
  trap 'echo ERR' ERR
  _cs_fetch_text() { return 7; }
  _pve_fetch_install_script >/dev/null || true
  echo "rc=done"
)"
expect "no curl output at all trips neither errexit nor the ERR trap" "rc=done" "$rc"

fetch_line=$(grep -n '_pve_fetch_install_script || exit' "$BACKEND" | cut -d: -f1)
create_line=$(grep -n '  create_lxc_container || exit' "$BACKEND" | cut -d: -f1)
expect "the script is fetched before the container is created" yes "$([[ -n "$fetch_line" && -n "$create_line" ]] && ((fetch_line < create_line)) && echo yes || echo no)"
expect "and not fetched a second time before the install" 1 "$(grep -c '_cs_fetch_text "install/${var_install}.sh"' "$BACKEND")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
