#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(_cs_mounts_under|_cs_clean_target_dir|fetch_and_deploy_gh_branch)\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

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

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
ensure_dependencies() { :; }
export STD=""
export HOME="$TEST_DIR/home"
mkdir -p "$HOME" "$TEST_DIR/bin" "$TEST_DIR/remote"

# Clones of github.com/<owner>/<repo> come from a local repository instead.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$TEST_DIR/remote/.insteadOf"
export GIT_CONFIG_VALUE_0="https://github.com/"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

eval "real$(declare -f _cs_mounts_under)"
_cs_mounts_under() {
  find "$TEST_DIR" -name 'mnt*' | sed 's/ /\\040/g; s|^|36 25 0:32 / |; s|$| rw - tmpfs tmpfs rw|' >"$TEST_DIR/mountinfo"
  real_cs_mounts_under "$1" "$2" "$TEST_DIR/mountinfo"
}

git init -q -b main "$TEST_DIR/remote/owner/app"
commit() {
  echo "$1" >"$TEST_DIR/remote/owner/app/app"
  git -C "$TEST_DIR/remote/owner/app" add app
  git -C "$TEST_DIR/remote/owner/app" commit -qm "$1"
}
commit v1

target="$TEST_DIR/opt/app"
installed_plain() {
  rm -rf "$TEST_DIR/opt"
  mkdir -p "$target/data"
  echo old >"$target/app"
  echo old >"$target/.env"
  echo keep >"$target/data/db"
}
installed_checkout() {
  rm -rf "$TEST_DIR/opt"
  mkdir -p "$TEST_DIR/opt"
  git clone -q "https://github.com/owner/app" "$target"
  echo old >"$target/app"
  git -C "$target" add app
  git -C "$target" commit -qm local
}
listing() { (cd "$target" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | tr '\n' ' '); }
content() { cat "$target/$1" 2>/dev/null || echo missing; }
leftovers() { find "$TEST_DIR/opt" -mindepth 1 -maxdepth 1 -name '.*' | wc -l | tr -d ' '; }
deploy() {
  local rc=0
  fetch_and_deploy_gh_branch app "$1" "" "$target" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

installed_checkout
check "clean: failed clone returns 22" "22" "$(CLEAN_INSTALL=1 deploy owner/missing)"
check "clean: failed clone leaves the checkout" "old" "$(content app)"
check "clean: failed clone leaves the .git" "yes" "$([[ -d "$target/.git" ]] && echo yes || echo no)"
check "clean: failed clone leaves no clone dir" "0" "$(leftovers)"

installed_plain
check "plain dir: failed clone returns 22" "22" "$(deploy owner/missing)"
check "plain dir: failed clone leaves the install" "./.env ./app ./data/db " "$(listing)"
check "plain dir: failed clone leaves no clone dir" "0" "$(leftovers)"

installed_plain
check "plain dir: clone returns 0" "0" "$(deploy owner/app)"
check "plain dir: clone replaces the install" "./app " "$(listing)"
check "plain dir: clone brings the .git" "yes" "$([[ -d "$target/.git" ]] && echo yes || echo no)"
check "plain dir: clone stamps the commit" "$(git -C "$TEST_DIR/remote/owner/app" rev-parse --short=7 HEAD)" "$(cat "$HOME/.app")"
check "plain dir: clone leaves no clone dir" "0" "$(leftovers)"

installed_checkout
check "clean: replaces a checkout" "0" "$(CLEAN_INSTALL=1 deploy owner/app)"
check "clean: takes the remote's content" "v1" "$(content app)"

installed_plain
check "keep: returns 0" "0" "$(CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP=".env data/db" deploy owner/app)"
check "keep: paths survive" "./.env ./app ./data/db " "$(listing)"
check "keep: kept file is untouched" "old" "$(content .env)"

installed_plain
mkdir -p "$target/mnt"
echo mounted >"$target/mnt/file"
check "mount: returns 0" "0" "$(CLEAN_INSTALL=1 deploy owner/app)"
check "mount: contents survive" "mounted" "$(content mnt/file)"

installed_plain
mkdir -p "$target/data/mnt"
echo mounted >"$target/data/mnt/file"
check "nested mount: returns 0" "0" "$(CLEAN_INSTALL=1 deploy owner/app)"
check "nested mount: contents survive" "mounted" "$(content data/mnt/file)"
check "nested mount: everything else goes" "./app ./data/mnt/file " "$(listing)"

# The engine runs under set -e, and rmdir fails on purpose on a mount's parent.
installed_plain
mkdir -p "$target/data/mnt"
check "set -e: the wipe does not end the script" "survived" "$(
  set -e -o pipefail
  _cs_clean_target_dir "$target"
  echo survived
)"

installed_plain
chmod 700 "$target"
check "mode: returns 0" "0" "$(CLEAN_INSTALL=1 deploy owner/app)"
check "mode: target takes the clone's mode" "0" "$(find "$target" -maxdepth 0 -perm 700 | wc -l | tr -d ' ')"

installed_plain
check "dot target: returns 0" "0" "$(cd "$target" && fetch_and_deploy_gh_branch app owner/app "" . >/dev/null 2>&1; echo $?)"
check "dot target: deploys" "v1" "$(content app)"
check "dot target: leaves no clone dir" "0" "$(leftovers)"

# A file that cannot be removed still stops the script, as rm -rf did.
if ((EUID != 0)); then
  installed_plain
  chmod 500 "$target/data"
  check "set -e: a failed removal ends the script" "" "$(
    set -e -o pipefail
    _cs_clean_target_dir "$target" 2>/dev/null
    echo survived
  )"
  chmod 700 "$target/data"
fi

rm -rf "$TEST_DIR/opt" "$TEST_DIR/real"
mkdir -p "$TEST_DIR/opt" "$TEST_DIR/real"
echo old >"$TEST_DIR/real/old"
ln -s "$TEST_DIR/real" "$target"
check "symlink: returns 0" "0" "$(CLEAN_INSTALL=1 deploy owner/app)"
check "symlink: stays a symlink" "yes" "$([[ -L "$target" ]] && echo yes || echo no)"
check "symlink: replaces what it points at" "app" "$(ls "$TEST_DIR/real")"
check "symlink: leaves no clone dir" "0" "$(leftovers)"

rm -rf "$TEST_DIR/opt"
check "fresh: creates the target and its parent" "0" "$(deploy owner/app)"
check "fresh: deploys" "v1" "$(content app)"

commit v2
echo stray >"$target/stray"
check "update: returns 0" "0" "$(deploy owner/app)"
check "update: takes the new commit" "v2" "$(content app)"
check "update: drops untracked files" "./app " "$(listing)"

echo "$passed passed, $failed failed"
((failed == 0))
