#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/alpine.func
source "$CORE_DIR/lib/alpine.func"

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

# The network and the host stay out of it. Every download hands over $archive.
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
net_resolves() { return 0; }
need_tool() { return 0; }
ensure_usr_local_bin_persist() { :; }
github_api_call() {
  jq -n --arg url "https://example.test/assets/$archive" \
    '{tag_name: "v1.0", tarball_url: $url, assets: [{browser_download_url: $url}]}' >"$2"
}
download_with_progress() { cp "$TEST_DIR/$archive" "$2"; }

export HOME="$TEST_DIR/home"
mkdir -p "$HOME" "$TEST_DIR/bin"

eval "real$(declare -f _cs_mounts_under)"
_cs_mounts_under() {
  find "$TEST_DIR" -name 'mnt*' | sed 's/ /\\040/g; s|^|36 25 0:32 / |; s|$| rw - tmpfs tmpfs rw|' >"$TEST_DIR/mountinfo"
  real_cs_mounts_under "$1" "$2" "$TEST_DIR/mountinfo"
}

mkdir -p "$TEST_DIR/src/app-1.0" "$TEST_DIR/flat" "$TEST_DIR/hollow/app-1.0"
echo new >"$TEST_DIR/src/app-1.0/app"
echo new >"$TEST_DIR/flat/app"
tar -czf "$TEST_DIR/good.tar.gz" -C "$TEST_DIR/src" app-1.0
tar -czf "$TEST_DIR/flat.tar.gz" -C "$TEST_DIR/flat" app
tar -czf "$TEST_DIR/hollow.tar.gz" -C "$TEST_DIR/hollow" app-1.0
head -c 64 "$TEST_DIR/good.tar.gz" >"$TEST_DIR/truncated.tar.gz"
echo "not a zip" >"$TEST_DIR/broken.zip"

target="$TEST_DIR/opt/app"
setup() {
  rm -rf "$TEST_DIR/opt"
  mkdir -p "$target/data"
  echo old >"$target/app"
  echo old >"$target/.env"
  echo keep >"$target/data/db"
}
listing() { (cd "$target" && find . -type f | LC_ALL=C sort | tr '\n' ' '); }
deploy() {
  local rc=0
  archive="$2"
  fetch_and_deploy_gh_release app owner/app "$1" latest "$target" "*${2##*.}" >/dev/null 2>&1 || rc=$?
  echo "$rc $(listing)"
}

installed="./.env ./app ./data/db "

for mode in tarball prebuild; do
  setup
  check "$mode: truncated archive leaves the install" "1 $installed" "$(CLEAN_INSTALL=1 deploy "$mode" truncated.tar.gz)"
  setup
  check "$mode: empty payload leaves the install" "1 $installed" "$(CLEAN_INSTALL=1 deploy "$mode" hollow.tar.gz)"
  setup
  check "$mode: clean install replaces the target" "0 ./app " "$(CLEAN_INSTALL=1 deploy "$mode" good.tar.gz)"
  setup
  check "$mode: without CLEAN_INSTALL it merges" "0 $installed" "$(deploy "$mode" good.tar.gz)"
  setup
  check "$mode: CLEAN_INSTALL_KEEP survives" "0 ./.env ./app ./data/db " "$(CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP=".env data/db" deploy "$mode" good.tar.gz)"
  setup
  mkdir -p "$target/mnt"
  echo mounted >"$target/mnt/file"
  check "$mode: mount point survives" "0 ./app ./mnt/file " "$(CLEAN_INSTALL=1 deploy "$mode" good.tar.gz)"
  setup
  mkdir -p "$target/data/mnt"
  echo mounted >"$target/data/mnt/file"
  check "$mode: nested mount survives" "0 ./app ./data/mnt/file " "$(CLEAN_INSTALL=1 deploy "$mode" good.tar.gz)"
done

setup
mkdir -p "$target/data/mnt bind"
echo mounted >"$target/data/mnt bind/file"
_cs_clean_target_dir "$target"
check "bind mount survives" "./data/mnt bind/file " "$(listing)"

setup
mv "$target" "$TEST_DIR/opt/real"
ln -s "$TEST_DIR/opt/real" "$target"
_cs_clean_target_dir "$target"
check "symlinked target stays and is emptied" "yes " "$([[ -L "$target" ]] && echo yes) $(listing)"

# The engine runs under set -e, and rmdir fails on purpose on a mount's parent.
setup
mkdir -p "$target/data/mnt"
check "set -e: the wipe does not end the script" "survived" "$(
  set -e -o pipefail
  _cs_clean_target_dir "$target"
  echo survived
)"

# A file that cannot be removed still stops the script, as rm -rf did.
if ((EUID != 0)); then
  setup
  chmod 500 "$target/data"
  check "set -e: a failed removal ends the script" "" "$(
    set -e -o pipefail
    _cs_clean_target_dir "$target" 2>/dev/null
    echo survived
  )"
  chmod 700 "$target/data"
fi

setup
check "tarball: no top-level directory leaves the install" "1 $installed" "$(CLEAN_INSTALL=1 deploy tarball flat.tar.gz)"
setup
check "prebuild: no top-level directory is deployed flat" "0 ./app " "$(CLEAN_INSTALL=1 deploy prebuild flat.tar.gz)"
if command -v unzip >/dev/null 2>&1; then
  setup
  check "prebuild: broken zip leaves the install" "1 $installed" "$(CLEAN_INSTALL=1 deploy prebuild broken.zip)"
fi

echo "$passed passed, $failed failed"
((failed == 0))
