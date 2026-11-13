#!/usr/bin/env bash
# Rivet ships its engine as a bare static binary on its own server; the helper
# only knew archives and refused it, so the script hand-rolled curl + chmod.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(fetch_and_deploy_from_url|_forge_workdir|_forge_disk_full)\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

# shellcheck disable=SC2034  # read by the eval'd helper
STD=""
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { echo "error: $*" >>"$TEST_DIR/log"; }
debug_log() { :; }
# Every URL is served from $TEST_DIR/srv/<file name>.
curl_download() { cp "$TEST_DIR/srv/${2##*/}" "$1"; }

mkdir -p "$TEST_DIR/srv"
cp "$(type -P true)" "$TEST_DIR/srv/engine-x86_64-unknown-linux-musl"
echo "not a program" >"$TEST_DIR/srv/notes.txt"

rc=0
fetch_and_deploy_from_url "https://example.test/engine-x86_64-unknown-linux-musl" "$TEST_DIR/opt/app" "engine" || rc=$?
check "a bare executable installs" 0 "$rc"
check "under the given name, executable" "yes" "$([[ -x "$TEST_DIR/opt/app/engine" ]] && echo yes || echo no)"
check "and runs" 0 "$("$TEST_DIR/opt/app/engine"; echo $?)"
check "no temporary file is left" "engine" "$(ls "$TEST_DIR/opt/app")"

rc=0
fetch_and_deploy_from_url "https://example.test/engine-x86_64-unknown-linux-musl" "$TEST_DIR/opt/plain" || rc=$?
check "without a name it keeps the URL's file name" "engine-x86_64-unknown-linux-musl" "$(ls "$TEST_DIR/opt/plain")"

# An update while the old binary runs: a rename leaves the running inode alone.
before="$(stat -c %i "$TEST_DIR/opt/app/engine")"
fetch_and_deploy_from_url "https://example.test/engine-x86_64-unknown-linux-musl" "$TEST_DIR/opt/app" "engine" >/dev/null
check "a second deploy replaces the file instead of writing into it" "changed" "$([[ "$(stat -c %i "$TEST_DIR/opt/app/engine")" != "$before" ]] && echo changed || echo same)"

rc=0
fetch_and_deploy_from_url "https://example.test/notes.txt" "$TEST_DIR/opt/txt" "notes" || rc=$?
check "a non-executable, non-archive is still refused" 65 "$rc"
check "and nothing is installed" "no" "$([[ -e "$TEST_DIR/opt/txt/notes" ]] && echo yes || echo no)"

echo "${passed} passed, ${failed} failed"
((failed == 0))
