#!/usr/bin/env bash
# A closed console sends SIGHUP to the whole foreground group. Since the run
# survives that, an unshielded pct start or template check failed instead:
# 10 runs in three days reported "would not start" for a container that came
# up, 5 "not available after download" for a template on disk.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$CORE_DIR/pve/backend.func"
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

if ! command -v setsid >/dev/null || [[ ! -r /proc/self/stat ]]; then
  echo "SKIP needs setsid and /proc"
  exit 0
fi

# Each stub hangs up its whole process group, as a closing console does, then does its work.
mkdir -p "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/pct" <<'EOF'
#!/usr/bin/env bash
case "$1" in
start)
  kill -HUP -- "-$(awk '{print $5}' /proc/$$/stat)"
  sleep 0.3
  : >"$MARK/started"
  echo "Started pve-container@$2.service"
  ;;
status) [[ -f "$MARK/started" ]] && echo "status: running" || echo "status: stopped" ;;
esac
EOF
cat >"$TEST_DIR/bin/pveam" <<'EOF'
#!/usr/bin/env bash
kill -HUP -- "-$(awk '{print $5}' /proc/$$/stat)"
sleep 0.3
echo "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst 129.66MB"
EOF
chmod +x "$TEST_DIR/bin/pct" "$TEST_DIR/bin/pveam"

{
  awk '/^_cs_shield_hangup[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func"
  awk '/^(_template_in_storage|_pct_restart)[(][)] [{]/,/^}/' "$BACKEND"
} >"$TEST_DIR/funcs.sh"

# In its own session, with the HUP trap the engine has, the way a console runs it.
run() {
  rm -f "$TEST_DIR/started"
  MARK="$TEST_DIR" PATH="$TEST_DIR/bin:$PATH" setsid -w bash -c '
    source "$1"
    trap ":" HUP
    msg_error() { :; }
    _pct_start_failed() { :; }
    TEMPLATE_STORAGE=local
    eval "$2"' _ "$TEST_DIR/funcs.sh" "$1" 2>/dev/null
}
started() { [[ -f "$TEST_DIR/started" ]] && echo started || echo aborted; }

run 'pct start 101 >/dev/null 2>&1'
expect "the stub's hangup kills an unshielded pct start (the old code)" aborted "$(started)"

out="$(run 'out="$(_cs_shield_hangup pct start 101 2>&1)"; echo "$out"')"
expect "a shielded pct start finishes" started "$(started)"
expect "and its output arrives in full" "Started pve-container@101.service" "$out"

expect "_pct_restart sees the container running" 0 "$(run '_pct_restart 101 "the config change"; echo $?')"

expect "the old template check loses a template on disk" 1 \
  "$(run 'pveam list local 2>/dev/null | grep -q debian-13-standard_13.6-1; echo $(($? != 0))')"
expect "the shielded check finds it" 0 \
  "$(run '_cs_shield_hangup _template_in_storage debian-13-standard_13.6-1_amd64.tar.zst; echo $?')"

expect "the start step uses the shield" 1 "$(grep -c '_start_out="$(_cs_shield_hangup pct start "$CTID" 2>&1)"' "$BACKEND")"
expect "both template checks use it" 2 "$(grep -c '_cs_shield_hangup _template_in_storage "$TEMPLATE"' "$BACKEND")"
expect "the pveam list | grep pipeline lives only in the helper" 1 "$(grep -c 'pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q' "$BACKEND" | tr -d ' ')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
