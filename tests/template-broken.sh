#!/usr/bin/env bash
# A template found locally skipped the catalog, so a corrupt one was kept
# ("no online version exists") and pct create failed on it at every retry.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$CORE_DIR/pve/backend.func"
eval "$(awk '/^_template_broken[(][)] [{]/,/^}/' "$BACKEND")"

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
broken() { _template_broken "$1" && echo broken || echo ok; }

mkdir -p "$TEST_DIR/root"
head -c 3000000 /dev/urandom >"$TEST_DIR/root/blob"
tar -C "$TEST_DIR/root" -czf "$TEST_DIR/good.tar.gz" blob
size=$(stat -c%s "$TEST_DIR/good.tar.gz")
head -c $((size / 2)) "$TEST_DIR/good.tar.gz" >"$TEST_DIR/cut.tar.gz"
cp "$TEST_DIR/good.tar.gz" "$TEST_DIR/flipped.tar.gz"
head -c 4096 /dev/zero | dd of="$TEST_DIR/flipped.tar.gz" bs=1 seek=$((size / 2)) conv=notrunc status=none
: >"$TEST_DIR/empty.tar.gz"
head -c 500000 "$TEST_DIR/good.tar.gz" >"$TEST_DIR/small.tar.gz"

expect "an intact template is kept" ok "$(broken "$TEST_DIR/good.tar.gz")"
expect "a missing template is fetched" broken "$(broken "$TEST_DIR/none.tar.gz")"
expect "an empty template is fetched" broken "$(broken "$TEST_DIR/empty.tar.gz")"
expect "a template under 1 MB is fetched" broken "$(broken "$TEST_DIR/small.tar.gz")"
expect "a cut-off download is fetched again" broken "$(broken "$TEST_DIR/cut.tar.gz")"
expect "damaged bytes inside are fetched again" broken "$(broken "$TEST_DIR/flipped.tar.gz")"

if command -v zstd >/dev/null; then
  tar -C "$TEST_DIR/root" --zstd -cf "$TEST_DIR/good.tar.zst" blob
  size=$(stat -c%s "$TEST_DIR/good.tar.zst")
  head -c $((size * 3 / 4)) "$TEST_DIR/good.tar.zst" >"$TEST_DIR/cut.tar.zst"
  expect "an intact zstd template is kept" ok "$(broken "$TEST_DIR/good.tar.zst")"
  expect "a cut-off zstd template is fetched again" broken "$(broken "$TEST_DIR/cut.tar.zst")"
fi

expect "every template check uses the helper, none keeps a broken file" "3 0" \
  "$(grep -c '_template_broken "$TEMPLATE_PATH"' "$BACKEND") $(grep -c 'no online version exists' "$BACKEND")"

# What pct create printed for a broken template, from the telemetry.
pattern="$(grep -oE "grep -qiE \"unable to open[^\"]*\"" "$BACKEND" | sed 's/^grep -qiE "//; s/"$//')"
expect "the retry after a failed create has its pattern" yes "$([[ -n "$pattern" ]] && echo yes || echo no)"
pattern="${pattern:-^-no pattern-$}"
for line in \
  "/*stdin*\\ : Decoding error (36) : Restored data doesn't match checksum" \
  "/*stdin*\\ : Read error (39) : premature end" \
  "tar: Unexpected EOF in archive"; do
  expect "a failed create retries with a fresh template: ${line##*: }" yes \
    "$(grep -qiE "$pattern" <<<"$line" && echo yes || echo no)"
done

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
