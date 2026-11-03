#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(_cs_clean_target_dir|_deploy_source_tarball|_deploy_unpacked_archive)\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

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

echo "${passed} passed, ${failed} failed"
((failed == 0))
