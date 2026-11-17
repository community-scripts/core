#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$CORE_DIR/api/errorlog.func"
eval "$(awk '/^(_incus_pull_guest_text|_incus_build_combined_log)[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"
eval "$(awk '/^(ensure_log_on_host|api_exit_script)[(][)] [{]/,/^}/' "$CORE_DIR/incus/build.func")"
explain_exit_code() { echo "General error"; }
# shellcheck disable=SC2034  # read by the eval'd helpers
GN="" CL="" BL=""

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
GUEST="$TEST_DIR/guest" HOST="$TEST_DIR/host"
mkdir -p "$GUEST/root" "$HOST/bin" "$HOST/logs" "$HOST/tmp" "$HOST/cwd"
MARKER="host-only-$$-$RANDOM"
printf '%s\n' "$MARKER" >"$HOST/secret.key"
chmod 600 "$HOST/secret.key"
passed=0 failed=0

# `file pull` as the 6.0.6/6.0.7 client does it: a guest symlink is re-created at
# the target, a file keeps the guest's mode, "-" streams the content with links
# resolved inside the guest. STUB_CLIENT=6.0.4 drops a guest symlink into the
# working directory instead, whatever the target.
cat >"$HOST/bin/incus" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-} ${2:-}" == "file pull" ]] || exit 0
src="$GUEST/${3#*/}" dst="$4"
[[ -e "$src" || -L "$src" ]] || exit 1
if [[ -L "$src" && "${STUB_CLIENT:-}" == 6.0.4 ]]; then
  ln -s "$(readlink "$src")" "$(basename "$src")"
elif [[ "$dst" == - ]]; then
  while [[ -L "$src" ]]; do
    link="$(readlink "$src")"
    [[ "$link" == /* ]] && src="$GUEST$link" || src="$(dirname "$src")/$link"
  done
  cat "$src"
elif [[ -L "$src" ]]; then
  ln -s "$(readlink "$src")" "$dst"
else
  cp "$src" "$dst" && chmod "$(stat -c %a "$src")" "$dst"
fi
EOF
chmod +x "$HOST/bin/incus"
export GUEST PATH="$HOST/bin:$PATH" TMPDIR="$HOST/tmp"

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# run <sid> - an install that failed in the container, as the host handles it:
# combined log, report, exit trap
# shellcheck disable=SC2034  # read by the eval'd helpers
run() {
  SESSION_ID="$1" CT_NAME=ct APP=Demo
  BUILD_LOG="$HOST/logs/incus-create-$1.log" INCUS_BUILD_LOG="$HOST/logs/incus-create-$1.log"
  combined_log="$HOST/logs/incus-install-$1-combined.log"
  printf '[2026-01-01 00:00:00] [INFO] Creating container\n[2026-01-01 00:00:05] [OK] Container started\n' >"$BUILD_LOG"
  (
    set -Eeuo pipefail
    cd "$HOST/cwd"
    post_update_to_api() {
      [[ -e "$HOST/trace-$SESSION_ID" ]] && return 0
      { build_error_string "$2"; printf '\nphase=%s\n' "$TM_ERR_PHASE"; } >"$HOST/trace-$SESSION_ID"
    }
    trap api_exit_script EXIT
    _incus_build_combined_log
    post_update_to_api failed 1
    exit 1
  ) >"$HOST/out-$1" 2>&1
}

# Links and setuid files on the host side whose name carries the session.
held() {
  {
    find "$HOST" -name "*$1*" \( -type l -o -perm -4000 \)
    find /tmp -maxdepth 1 -name "*$1*" \( -type l -o -perm -4000 \)
  } 2>/dev/null
}

# --- guest symlinks to a host file; the guest keeps a file at the same path ---
sid="sym$$"
ln -s "$HOST/secret.key" "$GUEST/root/.install-$sid.log"
ln -s "$HOST/secret.key" "$GUEST/root/.install-$sid.log.errinfo"
mkdir -p "$GUEST$HOST"
printf 'guest file\n' >"$GUEST$HOST/secret.key"
run "$sid"
expect "a guest symlink brings no host file into the logs, the report or the output" "" \
  "$(grep -l "$MARKER" "$combined_log" "$BUILD_LOG.install" "$HOST/trace-$sid" "$HOST/out-$sid" 2>/dev/null)"
expect "no symlink is left on the host" "" "$(held "$sid")"

sid="old$$"
ln -s "$HOST/secret.key" "$GUEST/root/.install-$sid.log"
ln -s "$HOST/secret.key" "$GUEST/root/.install-$sid.log.errinfo"
export STUB_CLIENT=6.0.4
run "$sid"
unset STUB_CLIENT
expect "a client that drops the link into the working directory leaves none" "" "$(held "$sid")"

# --- setuid files in the guest ---
sid="suid$$"
printf 'guest install log\n' >"$GUEST/root/.install-$sid.log"
printf '%s\n' EXIT_CODE=1 LINE=7 COMMAND=false PHASE=container '--- OUTPUT ---' boom >"$GUEST/root/.install-$sid.log.errinfo"
chmod 4755 "$GUEST/root/.install-$sid.log" "$GUEST/root/.install-$sid.log.errinfo"
run "$sid"
expect "no setuid file is left on the host" "" "$(held "$sid")"
expect "the capture still reaches the report" 1 "$(grep -c 'at line 7: false' "$HOST/trace-$sid")"

# --- an ordinary failure ---
sid="plain$$"
printf '%s\n' '[2026-01-01 00:01:00] [INFO] Installing Demo' 'E: Unable to locate package foo' >"$GUEST/root/.install-$sid.log"
printf '%s\n' EXIT_CODE=100 LINE=12 'COMMAND=apt-get install -y foo' 'STEP=Installing Demo' '--- OUTPUT ---' \
  'E: Unable to locate package foo' >"$GUEST/root/.install-$sid.log.errinfo"
run "$sid"
expect "the install log reaches the combined log" 1 "$(grep -c '^E: Unable to locate package foo$' "$combined_log")"
expect "the capture reaches the report" 1 "$(grep -c 'at line 12: apt-get install -y foo' "$HOST/trace-$sid")"
expect "a capture without PHASE is still the container's" container "$(sed -n 's/^phase=//p' "$HOST/trace-$sid")"
expect "the combined log is private" 600 "$(stat -c %a "$combined_log")"
expect "nothing pulled stays behind after the exit" "" "$(find "$HOST/tmp" -mindepth 1; find /tmp -maxdepth 1 -name "*$sid*")"

# --- size ---
head -c 5000 /dev/zero | tr '\0' x >"$GUEST/root/big"
CT_NAME=ct _incus_pull_guest_text /root/big "$HOST/logs/big" 1024 2>/dev/null
expect "a guest file is cut at the limit, into a private file" "1024 600" "$(stat -c '%s %a' "$HOST/logs/big" 2>/dev/null)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
