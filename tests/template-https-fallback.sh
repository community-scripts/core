#!/usr/bin/env bash
# pveam downloads templates over plain http. Hosts that could not reach port 80
# on download.proxmox.com ended with exit 222 although the same file answers
# over https.
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

eval "$(awk '/^_template_fetch_https[(][)] [{]/,/^}/' "$BACKEND" | sed "s#/var/lib/pve-manager/apl-info/download.proxmox.com#$TEST_DIR/catalog#")"

TPL=debian-13-standard_13.6-1_amd64.tar.zst
TEMPLATE_STORAGE=nas
DEST="$TEST_DIR/store/template/cache/$TPL"
printf 'the template' >"$TEST_DIR/payload"
SUM="$(sha512sum "$TEST_DIR/payload" | awk '{print $1}')"
cat >"$TEST_DIR/catalog" <<CATALOG
Package: debian-13-standard
Version: 13.6-1
Architecture: arm64
Location: system/debian-13-standard_13.6-1_arm64.tar.zst
md5sum: 80897e64290def95f3218aa30bbe5566
sha512sum: 0000

Package: debian-13-standard
Version: 13.6-1
Architecture: amd64
Location: system/$TPL
md5sum: a6148ff6f0d60e643a6e5f33497cecea
sha512sum: $SUM
Description: Debian 13 Trixie (standard)
CATALOG

pvesm() { echo "$TEST_DIR/store/template/cache/${2##*/}"; }
_cs_shield_hangup() { "$@"; }
curl() {
  local out="" url="${*: -1}"
  while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done
  echo "$url" >>"$TEST_DIR/urls"
  ((CURL_OK)) || return 7
  cp "$TEST_DIR/${SERVED:-payload}" "$out"
}

CURL_OK=1
_template_fetch_https "$TPL"
expect "the template is fetched over https" 0 "$?"
expect "from the path the catalog gives" "https://download.proxmox.com/images/system/$TPL" "$(cat "$TEST_DIR/urls")"
expect "into the storage's template directory" "the template" "$(cat "$DEST" 2>/dev/null)"
expect "leaving no partial file" 0 "$(find "$TEST_DIR/store" -name '*.part' | wc -l | tr -d ' ')"

rm -f "$DEST"
printf 'an error page' >"$TEST_DIR/wrong"
SERVED=wrong _template_fetch_https "$TPL"
expect "a download that does not match the catalog's sha512 is refused" 1 "$?"
expect "and nothing is left behind" 0 "$(find "$TEST_DIR/store" -type f | wc -l | tr -d ' ')"

CURL_OK=0
_template_fetch_https "$TPL"
expect "a failed download fails" 1 "$?"

: >"$TEST_DIR/urls"
CURL_OK=1
_template_fetch_https "turnkey-nextcloud-18.0-bookworm-amd64.tar.gz"
expect "a template the Proxmox catalog does not carry is not attempted" "1 0" "$? $(wc -l <"$TEST_DIR/urls" | tr -d ' ')"

expect "the download loop tries it before giving up" 1 \
  "$(awk '/if \[\[ \$attempt -eq 3 \]\]; then/,/exit 222/' "$BACKEND" | grep -c '_template_fetch_https "\$TEMPLATE"')"

echo "passed=${passed} failed=${failed}"
((failed == 0))
