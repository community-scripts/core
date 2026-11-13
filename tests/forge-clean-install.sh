#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(_cs_mounts_under|_cs_clean_target_dir|_deploy_source_tarball|_deploy_unpacked_archive|_forge_workdir|_forge_place|_forge_disk_full)\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

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

msg_error() { :; }
msg_warn() { :; }
ensure_dependencies() { :; }

# A target holding an installed app, and a fresh workdir, for each case.
setup() {
  rm -rf "$TEST_DIR/target" "$TEST_DIR/work"
  mkdir -p "$TEST_DIR/target/data" "$TEST_DIR/work"
  echo old >"$TEST_DIR/target/app"
  echo keep >"$TEST_DIR/target/data/db"
}
listing() { (cd "$TEST_DIR/target" && find . -type f | LC_ALL=C sort | tr '\n' ' '); }

mkdir -p "$TEST_DIR/src/app-1.0" "$TEST_DIR/flat" "$TEST_DIR/hollow/app-1.0"
echo new >"$TEST_DIR/src/app-1.0/app"
echo new >"$TEST_DIR/flat/app"
tar -czf "$TEST_DIR/good.tar.gz" -C "$TEST_DIR/src" app-1.0
tar -czf "$TEST_DIR/flat.tar.gz" -C "$TEST_DIR/flat" app
tar -czf "$TEST_DIR/hollow.tar.gz" -C "$TEST_DIR/hollow" app-1.0
head -c 64 "$TEST_DIR/good.tar.gz" >"$TEST_DIR/truncated.tar.gz"

unpacked() {
  local rc=0
  setup
  _deploy_unpacked_archive "$TEST_DIR/$1" "$TEST_DIR/target" "$TEST_DIR/work" >/dev/null 2>&1 || rc=$?
  echo "$rc $(listing)"
}
source_tarball() {
  local rc=0
  setup
  _deploy_source_tarball "$TEST_DIR/$1" "$TEST_DIR/target" "$TEST_DIR/work" >/dev/null 2>&1 || rc=$?
  echo "$rc $(listing)"
}

intact="./app ./data/db "
export CLEAN_INSTALL=1

check "archive: truncated download leaves the install" "251 $intact" "$(unpacked truncated.tar.gz)"
check "archive: empty payload leaves the install" "252 $intact" "$(unpacked hollow.tar.gz)"
check "archive: unsupported format leaves the install" "65 $intact" "$(unpacked good.rar)"
check "archive: clean install replaces the target" "0 ./app " "$(unpacked good.tar.gz)"
check "archive: no top-level dir replaces the target" "0 ./app " "$(unpacked flat.tar.gz)"
check "archive: new payload is in place" "new" "$(unpacked good.tar.gz >/dev/null; cat "$TEST_DIR/target/app")"
check "archive: CLEAN_INSTALL_KEEP survives" "0 ./app ./data/db " "$(CLEAN_INSTALL_KEEP="data" unpacked good.tar.gz)"
check "archive: without CLEAN_INSTALL it merges" "0 ./app ./data/db " "$(CLEAN_INSTALL=0 unpacked good.tar.gz)"

# The disk filling up mid-extraction: tar writes part of the payload, then fails.
mkdir "$TEST_DIR/bin"
printf '#!/usr/bin/env bash\n%q "$@"\nexit 2\n' "$(command -v tar)" >"$TEST_DIR/bin/tar"
chmod +x "$TEST_DIR/bin/tar"
check "archive: extraction that runs out of space leaves the install" "251 $intact" "$(PATH="$TEST_DIR/bin:$PATH" unpacked good.tar.gz)"
check "source: extraction that runs out of space leaves the install" "251 $intact" "$(PATH="$TEST_DIR/bin:$PATH" source_tarball good.tar.gz)"

check "source: truncated download leaves the install" "251 $intact" "$(source_tarball truncated.tar.gz)"
check "source: no top-level dir leaves the install" "251 $intact" "$(source_tarball flat.tar.gz)"
check "source: clean install replaces the target" "0 ./app " "$(source_tarball good.tar.gz)"
check "source: CLEAN_INSTALL_KEEP survives" "0 ./app ./data/db " "$(CLEAN_INSTALL_KEEP="data" source_tarball good.tar.gz)"

# Releases stage on disk, so a large one does not count against the memory limit.
workdir_under() {
  local dir rc=0
  dir="$(TMPDIR="$1" _forge_workdir)" || rc=$?
  echo "$rc ${dir%/*}"
  rm -rf -- "$dir"
}
mkdir "$TEST_DIR/staging"
check "workdir: TMPDIR wins" "0 $TEST_DIR/staging" "$(workdir_under "$TEST_DIR/staging")"
check "workdir: an unusable TMPDIR falls back to /tmp" "0 /tmp" "$(workdir_under "$TEST_DIR/missing")"
unset TMPDIR
default_workdir="$(_forge_workdir)"
check "workdir: defaults to /var/tmp, not /tmp" "/var/tmp" "${default_workdir%/*}"
rm -rf -- "$default_workdir"
check "no helper stages in the mktemp default" "0" "$(awk '/^(fetch_and_deploy_[a-z_]+|_forge_[a-z_]+)\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func" | grep -c '_tmp="\{0,1\}$(mktemp -d)\|tmpdir="\{0,1\}$(mktemp -d)')"

# _forge_place: nothing of the release stays behind in staging, and what the
# target already has is merged, not replaced.
rm -rf "$TEST_DIR/src" "$TEST_DIR/dst"
mkdir -p "$TEST_DIR/src/lib" "$TEST_DIR/src/data" "$TEST_DIR/dst/data"
echo new >"$TEST_DIR/src/app"
echo new >"$TEST_DIR/src/lib/a"
echo new >"$TEST_DIR/src/data/schema"
echo hidden >"$TEST_DIR/src/.env.example"
echo mine >"$TEST_DIR/dst/data/db"
rc=0
_forge_place "$TEST_DIR/src" "$TEST_DIR/dst" || rc=$?
check "place: succeeds" 0 "$rc"
check "place: staging is empty afterwards" "" "$(ls -A "$TEST_DIR/src")"
check "place: new entries arrive, dotfiles included" "new new hidden" "$(cat "$TEST_DIR/dst/app" "$TEST_DIR/dst/lib/a" "$TEST_DIR/dst/.env.example" | xargs)"
check "place: an existing directory is merged" "mine new" "$(cat "$TEST_DIR/dst/data/db" "$TEST_DIR/dst/data/schema" | xargs)"

df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 4000000 4000000 %s 100%% /\n' "${FAKE_AVAIL:-0}"; }
rc=0
FAKE_AVAIL=12 _forge_disk_full "$TEST_DIR/dst" || rc=$?
check "a full disk is reported" 1 "$rc"
rc=0
FAKE_AVAIL=900000 _forge_disk_full "$TEST_DIR/dst" || rc=$?
check "a failure with space left is not blamed on the disk" 0 "$rc"

cat >"$TEST_DIR/mountinfo" <<'EOF'
22 1 0:20 / / rw - ext4 /dev/root rw
30 22 0:25 / /opt/app rw - zfs tank/app rw
31 30 0:26 / /opt/app/media\040library rw - nfs srv:/media rw
32 30 0:27 /cfg.yml /opt/app/config.yml rw - ext4 /dev/sdb rw
33 22 0:28 / /opt/app2 rw - tmpfs tmpfs rw
EOF
mounts_of() {
  local -a found=()
  _cs_mounts_under "$1" found "$TEST_DIR/mountinfo"
  printf '%s|' "${found[@]}"
}
check "mountinfo: mounts below the target, decoded" "/opt/app/media library|/opt/app/config.yml|" "$(mounts_of /opt/app)"
rc=0
_cs_mounts_under /opt/app found "$TEST_DIR/no-mountinfo" || rc=$?
check "mountinfo: unreadable is an error" 1 "$rc"

eval "real$(declare -f _cs_mounts_under)"
_cs_mounts_under() {
  find "$TEST_DIR" -name 'mnt*' | sed 's/ /\\040/g; s|^|36 25 0:32 / |; s|$| rw - tmpfs tmpfs rw|' >"$TEST_DIR/mountinfo"
  real_cs_mounts_under "$1" "$2" "$TEST_DIR/mountinfo"
}
mkdir -p "$TEST_DIR/bin-count"
printf '#!/usr/bin/env bash\necho x >>"%s"\nexit 1\n' "$TEST_DIR/mountpoint.calls" >"$TEST_DIR/bin-count/mountpoint"
chmod +x "$TEST_DIR/bin-count/mountpoint"
rm -rf "$TEST_DIR/target"
for i in $(seq 40); do mkdir -p "$TEST_DIR/target/node_modules/p$i/lib" && echo x >"$TEST_DIR/target/node_modules/p$i/lib/index.js"; done
mkdir -p "$TEST_DIR/target/data/mnt media" "$TEST_DIR/target/mnt[x]" "$TEST_DIR/target/a*b"
echo mounted >"$TEST_DIR/target/data/mnt media/file"
echo mounted >"$TEST_DIR/target/mnt[x]/file"
echo mounted >"$TEST_DIR/target/mnt.conf"
echo gone >"$TEST_DIR/target/a*b/file"
PATH="$TEST_DIR/bin-count:$PATH" _cs_clean_target_dir "$TEST_DIR/target"
check "mounts: a mounted directory and a mounted file survive, the rest goes" "./data/mnt media/file ./mnt.conf ./mnt[x]/file " "$(listing)"
check "mounts: no process per directory" 0 "$(cat "$TEST_DIR/mountpoint.calls" 2>/dev/null | wc -l | tr -d ' ')"

# The tarball mode used to return 0 whatever cp did.
setup
mkdir -p "$TEST_DIR/pkg/app-1.0" && echo v1 >"$TEST_DIR/pkg/app-1.0/app"
tar -czf "$TEST_DIR/work/app.tar.gz" -C "$TEST_DIR/pkg" app-1.0
_forge_place() { return 1; }
rc=0
FAKE_AVAIL=0 _deploy_source_tarball "$TEST_DIR/work/app.tar.gz" "$TEST_DIR/target" "$TEST_DIR/work" || rc=$?
check "tarball: a full disk ends the deploy" 252 "$rc"

echo "${passed} passed, ${failed} failed"
((failed == 0))
