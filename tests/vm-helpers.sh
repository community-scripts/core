#!/usr/bin/env bash
# Host-independent regression tests for vm/common.func and the qm helpers in
# pve/vm-core.func. Every host command (qm, curl, apt-get, virt-customize) is
# mocked; nothing is downloaded or created.
set -euo pipefail

COMMUNITY_SCRIPTS_CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export COMMUNITY_SCRIPTS_CORE_DIR
pveversion() { :; }
# shellcheck disable=SC1091
source "${COMMUNITY_SCRIPTS_CORE_DIR}/pve/vm-core.func"
load_cloud_init_functions
set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/calls.log"
ERRORS="$TEST_DIR/errors.log"
WARNINGS="$TEST_DIR/warnings.log"
CL="" BL="" GN="" TAB="  " DGN="" BGN="" INFO="" BOLD="" YW="" STD=""
passed=0

# Windows' jq writes CRLF; the engine only ever runs where it does not.
if [[ "$(uname -s)" == *_NT* || "$(uname -o 2>/dev/null)" == Cygwin || "$(uname -o 2>/dev/null)" == Msys ]]; then
  jq() { command jq "$@" | tr -d '\r'; }
fi

msg_info() { :; }
msg_ok() { :; }
msg_error() { printf '%s\n' "$*" >>"$ERRORS"; }
msg_warn() { printf '%s\n' "$*" >>"$WARNINGS"; }
_ci_msg_info() { :; }
_ci_msg_ok() { :; }
_ci_msg_warn() { printf '%s\n' "$*" >>"$WARNINGS"; }
sleep() { :; }

reset_logs() { : >"$LOG"; : >"$ERRORS"; : >"$WARNINGS"; }

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ -s "$ERRORS" ]] && sed 's/^/  error: /' "$ERRORS" >&2
  exit 1
}
assert_eq() { [[ "$1" == "$2" ]] || fail "${3:-value}: expected <$2>, got <$1>"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "${3:-$1} does not contain <$2>"; }
ok() {
  passed=$((passed + 1))
  printf 'ok %d - %s\n' "$passed" "$1"
}

# ── curl mock ───────────────────────────────────────────────────────────────
# URL -> fixture file. -o writes it, -I/-w answer from MOCK_STATUS_<n>.
declare -A FIXTURE=()
declare -A HEAD_OK=()
# A file, not an array: curl -w runs inside a command substitution.
HTTP_CODES_FILE="$TEST_DIR/http-codes"
http_codes() { printf '%s\n' "$@" >"$HTTP_CODES_FILE"; }
curl() {
  local url="" out="" head=no write=""
  while (($#)); do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) write="$2"; shift 2 ;;
    --max-time | --retry | --retry-delay | --connect-timeout) shift 2 ;;
    -*I*) head=yes; shift ;;
    http*://*) url="$1"; shift ;;
    *) shift ;;
    esac
  done
  printf 'curl %s %s\n' "$head" "$url" >>"$LOG"

  if [[ -n "$write" ]]; then
    local code
    code="$(head -n 1 "$HTTP_CODES_FILE" 2>/dev/null)"
    sed -i '1d' "$HTTP_CODES_FILE" 2>/dev/null || true
    code="${code:-000}"
    printf '%s' "$code"
    [[ "$code" == 000 ]] && return 7
    return 0
  fi
  if [[ "$head" == yes ]]; then
    [[ -n "${HEAD_OK[$url]:-}" ]] && return 0
    return 22
  fi
  [[ -n "${FIXTURE[$url]:-}" ]] || return 22
  if [[ -n "$out" && "$out" != /dev/null ]]; then
    cp -- "${FIXTURE[$url]}" "$out"
  else
    cat -- "${FIXTURE[$url]}"
  fi
}

fixture() {
  local url="$1" file
  file="$TEST_DIR/fixture-$(printf '%s' "$url" | sha256sum | cut -c1-16)"
  cat >"$file"
  FIXTURE[$url]="$file"
}

# ── checksums ───────────────────────────────────────────────────────────────
IMAGE="$TEST_DIR/image.img"
printf 'pretend image\n' >"$IMAGE"
IMAGE_SHA256="$(sha256sum "$IMAGE" | awk '{print $1}')"
IMAGE_SHA512="$(sha512sum "$IMAGE" | awk '{print $1}')"

fixture "https://sums.test/gnu" <<EOF
0000000000000000000000000000000000000000000000000000000000000000 *other.img
${IMAGE_SHA256} *openwrt.img.gz
EOF
assert_eq "$(_vm_checksum_from_sums https://sums.test/gnu openwrt.img.gz)" "sha256sum ${IMAGE_SHA256}" "GNU binary-mode line"
ok "GNU checksum list with *file"

fixture "https://sums.test/bsd" <<EOF
SHA256 (FreeBSD-other.qcow2.xz) = 1111111111111111111111111111111111111111111111111111111111111111
SHA256 (FreeBSD-15.1-RELEASE-amd64-ufs.qcow2.xz) = ${IMAGE_SHA256^^}
EOF
assert_eq "$(_vm_checksum_from_sums https://sums.test/bsd FreeBSD-15.1-RELEASE-amd64-ufs.qcow2.xz)" \
  "sha256sum ${IMAGE_SHA256}" "BSD line, upper-case hash"
ok "BSD checksum list is read and lower-cased"

fixture "https://sums.test/turnkey" <<EOF
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

    \$ sha256sum turnkey-nextcloud.iso
      ${IMAGE_SHA256}  turnkey-nextcloud.iso
    \$ sha512sum turnkey-nextcloud.iso
      ${IMAGE_SHA512}  turnkey-nextcloud.iso
EOF
assert_eq "$(_vm_checksum_from_sums https://sums.test/turnkey turnkey-nextcloud.iso)" \
  "sha256sum ${IMAGE_SHA256}" "TurnKey signed hash file"
ok "TurnKey .hash skips the '\$ sha256sum file' line"

fixture "https://sums.test/bare" <<<"  ${IMAGE_SHA512}  "
assert_eq "$(_vm_checksum_from_sums https://sums.test/bare anything)" "sha512sum ${IMAGE_SHA512}" "bare hash"
ok "bare hash file, algorithm from its length"

if _vm_checksum_from_sums https://sums.test/gnu missing.img >/dev/null; then fail "a file absent from the list must not resolve"; fi
if _vm_checksum_from_sums https://sums.test/unreachable openwrt.img.gz >/dev/null; then fail "an unreachable list must not resolve"; fi
ok "absent entry and unreachable list return non-zero"

reset_logs
fixture "https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/sha256sums" <<EOF
${IMAGE_SHA256} *openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz
EOF
assert_eq "$(vm_image_checksum https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz)" \
  "sha256sum ${IMAGE_SHA256}" "OpenWrt mapping"
assert_contains "$LOG" "https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/sha256sums"
for url in \
  "https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/FreeBSD-15.1-RELEASE-amd64-ufs.qcow2.xz|https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/CHECKSUM.SHA256" \
  "https://mirror.turnkeylinux.org/turnkeylinux/images/iso/turnkey-nextcloud-19.0-trixie-amd64.iso|https://mirror.turnkeylinux.org/turnkeylinux/images/iso/turnkey-nextcloud-19.0-trixie-amd64.iso.hash" \
  "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2|https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS"; do
  reset_logs
  vm_image_checksum "${url%%|*}" >/dev/null || true
  assert_contains "$LOG" "${url#*|}"
done
if vm_image_checksum "https://sourceforge.net/projects/x/files/a.iso/download" >/dev/null; then fail "unknown hosts have no checksum"; fi
ok "vendor checksum files are derived from the download URL"

# ── vm_fetch_image checksum options ─────────────────────────────────────────
fixture "https://dl.test/openwrt.img.gz" <"$IMAGE"
reset_logs
vm_fetch_image "https://dl.test/openwrt.img.gz" "$TEST_DIR/cache/openwrt.img.gz" --checksum-url https://sums.test/gnu ||
  fail "--checksum-url with a matching hash must succeed"
[[ -s "$TEST_DIR/cache/openwrt.img.gz" ]] || fail "verified download was not moved into place"
ok "vm_fetch_image --checksum-url verifies by the target's file name"

reset_logs
if vm_fetch_image "https://dl.test/openwrt.img.gz" "$TEST_DIR/cache/bad.img" --sha256 "$(printf '%064d' 0)"; then
  fail "a sha256 mismatch must fail"
fi
[[ ! -e "$TEST_DIR/cache/bad.img" && ! -e "$TEST_DIR/cache/bad.img.part" ]] || fail "a rejected download must leave nothing behind"
assert_contains "$ERRORS" "mismatch"
ok "vm_fetch_image --sha256 mismatch fails and removes the partial file"

reset_logs
vm_fetch_image "https://dl.test/openwrt.img.gz" "$TEST_DIR/cache/upper.img" --sha256 "${IMAGE_SHA256^^}" ||
  fail "an upper-case digest must match"
vm_fetch_image "https://dl.test/openwrt.img.gz" "$TEST_DIR/cache/nosums.img" --checksum-url https://sums.test/unreachable ||
  fail "an unavailable checksum list falls back to the size checks"
assert_contains "$WARNINGS" "checking the size only"
ok "digest case is ignored; missing checksum list warns and continues"

# ── vm_import_disk ──────────────────────────────────────────────────────────
VMID=100
QM_MODERN=yes
QM_IMPORT_RC=0
QM_IMPORT_OUT=""
QM_CONFIG_BEFORE=""
QM_CONFIG_AFTER=""
# A file, not a variable: the import runs inside a command substitution.
QM_IMPORTED_FLAG="$TEST_DIR/qm-imported"
qm() {
  printf 'qm %s\n' "$*" >>"$LOG"
  case "$1 ${2:-}" in
  "disk import")
    if [[ "${3:-}" == --help ]]; then [[ "$QM_MODERN" == yes ]]; return; fi
    : >"$QM_IMPORTED_FLAG"
    printf '%s\n' "$QM_IMPORT_OUT"
    return "$QM_IMPORT_RC"
    ;;
  "importdisk "*)
    : >"$QM_IMPORTED_FLAG"
    printf '%s\n' "$QM_IMPORT_OUT"
    return "$QM_IMPORT_RC"
    ;;
  "config "*)
    if [[ -e "$QM_IMPORTED_FLAG" ]]; then printf '%s\n' "$QM_CONFIG_AFTER"; else printf '%s\n' "$QM_CONFIG_BEFORE"; fi
    ;;
  "guest cmd")
    case "$4" in
    ping) [[ "${GUEST_PING:-yes}" == yes ]] ;;
    network-get-interfaces) printf '%s\n' "$GUEST_IFACES" ;;
    esac
    ;;
  "guest exec") printf '%s\n' "$GUEST_EXEC_JSON" ;;
  "start "*) return "${QM_START_RC:-0}" ;;
  *) return 0 ;;
  esac
}

import_case() {
  rm -f "$QM_IMPORTED_FLAG"
  reset_logs
  VM_IMPORTED_DISK="stale"
}

import_case
DISK_IMPORT_FORMAT=raw
QM_IMPORT_OUT="transferred 1.0 GiB of 1.0 GiB (100.00%)
unused0: successfully imported disk 'local-lvm:vm-100-disk-1'"
vm_import_disk 100 "$IMAGE" local-lvm || fail "modern import"
assert_eq "$VM_IMPORTED_DISK" "local-lvm:vm-100-disk-1" "volume from qm's report"
assert_contains "$LOG" "qm disk import 100 $IMAGE local-lvm --format raw"
ok "vm_import_disk uses qm disk import and the reported volume"

import_case
QM_MODERN=no
vm_import_disk 100 "$IMAGE" local-lvm qcow2 || fail "legacy import"
assert_contains "$LOG" "qm importdisk 100 $IMAGE local-lvm --format qcow2"
QM_MODERN=yes
ok "vm_import_disk falls back to qm importdisk and honours an explicit format"

import_case
QM_IMPORT_OUT="transferred 1.0 GiB of 1.0 GiB (100.00%)"
QM_CONFIG_BEFORE=$'boot: order=scsi0\nunused0: local-lvm:vm-100-disk-9'
QM_CONFIG_AFTER=$'boot: order=scsi0\nunused0: local-lvm:vm-100-disk-9\nunused1: local-lvm:vm-100-disk-10'
vm_import_disk 100 "$IMAGE" local-lvm || fail "import without a report line"
assert_eq "$VM_IMPORTED_DISK" "local-lvm:vm-100-disk-10" "new unused entry, not the lexically last"
ok "vm_import_disk reads the new unusedN entry (disk-10 after disk-9)"

import_case
QM_IMPORT_OUT="storage 'local-lvm' does not exist"
QM_IMPORT_RC=255
if vm_import_disk 100 "$IMAGE" local-lvm 2>/dev/null; then fail "a failed import must fail"; fi
assert_eq "$VM_IMPORTED_DISK" "" "no volume after a failed import"
QM_IMPORT_RC=0
ok "vm_import_disk reports a failed import instead of swallowing it"

import_case
QM_IMPORT_OUT="done"
QM_CONFIG_BEFORE="unused0: local-lvm:vm-100-disk-1"
QM_CONFIG_AFTER="unused0: local-lvm:vm-100-disk-1"
if vm_import_disk 100 "$IMAGE" local-lvm 2>/dev/null; then fail "an unidentifiable volume must fail"; fi
assert_contains "$ERRORS" "could not tell which volume"
QM_CONFIG_BEFORE="" QM_CONFIG_AFTER=""
ok "vm_import_disk never guesses a volume name"

# ── guest agent and IP ──────────────────────────────────────────────────────
GUEST_IFACES='[
 {"name":"lo","hardware-address":"00:00:00:00:00:00","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"127.0.0.1"}]},
 {"name":"docker0","hardware-address":"02:42:aa:bb:cc:dd","ip-addresses":[{"ip-address-type":"ipv4","ip-address":"172.17.0.1"}]},
 {"name":"ens18","hardware-address":"02:ab:cd:ef:01:23","ip-addresses":[
   {"ip-address-type":"ipv4","ip-address":"169.254.10.10"},
   {"ip-address-type":"ipv6","ip-address":"fe80::1"},
   {"ip-address-type":"ipv4","ip-address":"192.168.1.50"}]}
]'
assert_eq "$(get_vm_ip 100 2 02:AB:CD:EF:01:23)" "192.168.1.50" "MAC match, case-insensitive"
assert_eq "$(get_vm_ip 100 2)" "192.168.1.50" "no MAC: Docker bridge and link-local skipped"
if get_vm_ip 100 2 02:00:00:00:00:99 >/dev/null; then fail "an unknown MAC must not return an address"; fi
ok "get_vm_ip matches the NIC by MAC and skips container bridges"

MAC="02:AB:CD:EF:01:23" START_VM=yes
vm_wait_for_ip 4 || fail "vm_wait_for_ip"
assert_eq "$VM_IP" "192.168.1.50" "vm_wait_for_ip"
START_VM=no
if vm_wait_for_ip 4; then fail "a stopped VM has no IP to wait for"; fi
assert_eq "$VM_IP" "" "VM_IP cleared for a stopped VM"
START_VM=yes
ok "vm_wait_for_ip sets VM_IP only for a started VM"

GUEST_EXEC_JSON='{"exited":1,"exitcode":3,"out-data":"hello\n"}'
rc=0
out="$(vm_guest_exec 100 30 -- echo hello)" || rc=$?
assert_eq "$rc" 3 "guest exit code"
assert_eq "$out" "hello" "guest stdout"
GUEST_EXEC_JSON='{"exited":0,"pid":42}'
rc=0
vm_guest_exec 100 30 sleep 99 >/dev/null || rc=$?
assert_eq "$rc" 124 "still running"
ok "vm_guest_exec returns the guest's exit code, 124 when still running"

GUEST_PING=yes
vm_wait_guest_agent 100 6 || fail "agent answers"
GUEST_PING=no
if vm_wait_guest_agent 100 6; then fail "a silent agent must time out"; fi
GUEST_PING=yes
ok "vm_wait_guest_agent"

reset_logs
GUEST_EXEC_JSON='{"exited":1,"exitcode":2,"out-data":"status: degraded done\n"}'
wait_for_cloud_init 100 30 || fail "degraded cloud-init still completed"
assert_contains "$WARNINGS" "recoverable errors"
GUEST_EXEC_JSON='{"exited":1,"exitcode":1}'
if wait_for_cloud_init 100 30; then fail "a cloud-init error must be reported"; fi
ok "wait_for_cloud_init uses the guest agent and maps cloud-init's exit codes"

reset_logs
QM_START_RC=0 START_VM=yes
vm_start_vm "Test VM"
assert_contains "$LOG" "qm start 100"
reset_logs
START_VM=no
vm_start_vm
[[ ! -s "$LOG" ]] || fail "START_VM=no must not start the VM"
START_VM=yes
ok "vm_start_vm honours START_VM"

# ── release and index discovery ─────────────────────────────────────────────
FORGE_JSON=""
_forge_release_json() {
  printf '%s %s %s\n' "$1" "$2" "$3" >>"$LOG"
  [[ -n "$FORGE_JSON" ]] || return 22
  printf '%s\n' "$FORGE_JSON" >"$5"
}

reset_logs
FORGE_JSON='{"tag_name":"v1.5.4","assets":[
  {"name":"zimaos-x86_64-1.5.4.img","browser_download_url":"https://gh.test/a.img","digest":"sha256:'"${IMAGE_SHA256^^}"'"},
  {"name":"zimaos-x86_64-1.5.4_installer.iso","browser_download_url":"https://gh.test/b.iso","digest":"sha256:'"${IMAGE_SHA256}"'"}]}'
vm_release_asset github IceWhaleTech/ZimaOS 'zimaos-x86_64-.*_installer\.iso$' || fail "release asset"
assert_eq "$VM_RELEASE_TAG" "v1.5.4" "tag"
assert_eq "$VM_RELEASE_VERSION" "1.5.4" "version"
assert_eq "$VM_RELEASE_ASSET" "zimaos-x86_64-1.5.4_installer.iso" "asset"
assert_eq "$VM_RELEASE_URL" "https://gh.test/b.iso" "url"
assert_eq "$VM_RELEASE_SHA256" "$IMAGE_SHA256" "digest"
assert_contains "$LOG" "github IceWhaleTech/ZimaOS latest"
ok "vm_release_asset picks the matching GitHub asset and its digest"

FORGE_JSON='{"tag_name":"16.0","assets":{"links":[{"name":"haos.qcow2.xz","url":"https://gl.test/x","direct_asset_url":"https://gl.test/direct"}]}}'
vm_release_asset gitlab group/project 'qcow2\.xz$' 16.0 || fail "gitlab release asset"
assert_eq "$VM_RELEASE_URL" "https://gl.test/direct" "GitLab direct asset URL"
assert_eq "$VM_RELEASE_SHA256" "" "GitLab publishes no digest"
ok "vm_release_asset reads GitLab asset links"

reset_logs
FORGE_JSON='{"tag_name":"v2","assets":[{"name":"other.iso","browser_download_url":"https://gh.test/o"}]}'
if vm_release_asset github a/b 'installer\.iso$'; then fail "no matching asset must fail"; fi
assert_eq "$VM_RELEASE_URL" "" "no URL without a match"
FORGE_JSON=""
if vm_release_asset github a/b 'x'; then fail "an unreadable release must fail"; fi
ok "vm_release_asset fails without a matching asset or release"

fixture "https://index.test/freebsd/" <<'EOF'
<a href="14.4-RELEASE/">14.4-RELEASE/</a>
<a href="14.10-RELEASE/">14.10-RELEASE/</a>
<a href="14.9-RELEASE/">14.9-RELEASE/</a>
<a href="15.1-RELEASE/">15.1-RELEASE/</a>
EOF
vm_latest_from_index "https://index.test/freebsd/" '14\.[0-9]+-RELEASE' || fail "index"
assert_eq "$VM_INDEX_LATEST" "14.10-RELEASE" "version order, not lexical"
ok "vm_latest_from_index orders by version"

HEAD_OK["https://index.test/freebsd/14.9-RELEASE/img-ufs.qcow2.xz"]=1
vm_latest_from_index "https://index.test/freebsd/" '14\.[0-9]+-RELEASE' \
  --probe 'https://index.test/freebsd/{}/img.qcow2.xz' \
  --probe 'https://index.test/freebsd/{}/img-ufs.qcow2.xz' || fail "probe"
assert_eq "$VM_INDEX_LATEST" "14.9-RELEASE" "newest entry with a file"
assert_eq "$VM_INDEX_URL" "https://index.test/freebsd/14.9-RELEASE/img-ufs.qcow2.xz" "probed URL"
ok "vm_latest_from_index --probe skips releases without files and tries every template"

fixture "https://index.test/bliss/" <<'EOF'
Bliss-v16.9.7-x86_64-OFFICIAL-foss-20250101.iso
Bliss-v16.9.10-x86_64-OFFICIAL-foss-20240601.iso
Bliss-v16.9.7-x86_64-OFFICIAL-foss-20250315.iso
Bliss-v16.9.7-x86_64-OFFICIAL-foss-20250315.iso
EOF
vm_latest_from_index "https://index.test/bliss/" 'Bliss-v[0-9.]+-x86_64-OFFICIAL-foss-[0-9]{8}\.iso' \
  --sort-by 'foss-\K[0-9]{8}' || fail "sort-by"
assert_eq "$VM_INDEX_LATEST" "Bliss-v16.9.7-x86_64-OFFICIAL-foss-20250315.iso" "newest build date"
ok "vm_latest_from_index --sort-by orders by the selected key"

reset_logs
if vm_latest_from_index "https://index.test/freebsd/" '99\.[0-9]+-RELEASE'; then fail "no match must fail"; fi
assert_eq "$VM_INDEX_LATEST" "" "no stale value"
if vm_latest_from_index "https://index.test/missing/" 'x'; then fail "an unreadable index must fail"; fi
if vm_latest_from_index "https://index.test/freebsd/" '14\.[0-9]+-RELEASE' --probe 'https://none.test/{}'; then
  fail "no probed file must fail"
fi
ok "vm_latest_from_index fails instead of falling back"

# ── vm_firstboot_unit ───────────────────────────────────────────────────────
CUSTOMIZE_FAIL=no
_vm_customize() {
  local label="$1"
  shift 2
  printf 'customize %s %s\n' "$label" "$*" >>"$LOG"
  while (($#)); do
    if [[ "$1" == --upload && "$2" == *:/etc/systemd/system/* ]]; then
      cp -- "${2%%:*}" "$TEST_DIR/unit.service"
    fi
    shift
  done
  [[ "$CUSTOMIZE_FAIL" == yes ]] && _VM_PREPARE_FAILED+=("$label")
  return 0
}
printf '#!/bin/bash\nset -Eeuo pipefail\necho hi\n' >"$TEST_DIR/setup.sh"

reset_logs
vm_firstboot_unit "$IMAGE" app-setup "$TEST_DIR/setup.sh" --cloud-init yes --after docker.service \
  --requires-path /opt/app.bin --description "App setup" || fail "first-boot unit"
UNIT="$TEST_DIR/unit.service"
assert_contains "$UNIT" "After=network-online.target cloud-final.service docker.service"
assert_contains "$UNIT" "Wants=network-online.target cloud-final.service docker.service"
assert_contains "$UNIT" "WantedBy=cloud-init.target"
assert_contains "$UNIT" "ConditionPathExists=!/var/lib/community-scripts/app-setup.done"
assert_contains "$UNIT" "ConditionPathExists=/opt/app.bin"
assert_contains "$UNIT" "ExecStart=/usr/local/sbin/app-setup"
assert_contains "$UNIT" "touch /var/lib/community-scripts/app-setup.done"
assert_contains "$UNIT" "Type=oneshot"
assert_contains "$UNIT" "Description=App setup"
assert_contains "$LOG" "--chmod 0755:/usr/local/sbin/app-setup"
assert_contains "$LOG" "--run-command systemctl enable app-setup.service"
assert_eq "$VM_FIRSTBOOT_MARKER" "/var/lib/community-scripts/app-setup.done" "marker"
grep -q 'multi-user.target' "$UNIT" && fail "a Cloud-Init unit must not involve multi-user.target"
ok "vm_firstboot_unit with Cloud-Init: cloud-init.target after cloud-final, no cycle"

vm_firstboot_unit "$IMAGE" app-setup "$TEST_DIR/setup.sh" --cloud-init no || fail "first-boot without CI"
assert_contains "$UNIT" "WantedBy=multi-user.target"
grep -q 'cloud-final' "$UNIT" && fail "without Cloud-Init there is no cloud-final dependency"
ok "vm_firstboot_unit without Cloud-Init: multi-user.target"

USE_CLOUD_INIT=yes
vm_firstboot_unit "$IMAGE" app-setup "$TEST_DIR/setup.sh" || fail "first-boot default"
assert_contains "$UNIT" "WantedBy=cloud-init.target"
unset USE_CLOUD_INIT
ok "vm_firstboot_unit follows USE_CLOUD_INIT by default"

_VM_PREPARE_FAILED=()
CUSTOMIZE_FAIL=no
vm_customize "Docker" "$IMAGE" --run-command true || fail "a successful step returns 0"
CUSTOMIZE_FAIL=yes
if vm_customize "Docker" "$IMAGE" --run-command false; then fail "a failed step must return non-zero"; fi
CUSTOMIZE_FAIL=no
_VM_PREPARE_FAILED=()
ok "vm_customize returns the step's failure"

rc=0
vm_firstboot_unit "$IMAGE" "Bad Name" "$TEST_DIR/setup.sh" || rc=$?
assert_eq "$rc" 2 "invalid unit name"
rc=0
vm_firstboot_unit "$IMAGE" app "$TEST_DIR/missing.sh" || rc=$?
assert_eq "$rc" 1 "unreadable script"
CUSTOMIZE_FAIL=yes
_VM_PREPARE_FAILED=()
if vm_firstboot_unit "$IMAGE" app "$TEST_DIR/setup.sh"; then fail "a failed image change must be reported"; fi
CUSTOMIZE_FAIL=no
ok "vm_firstboot_unit rejects bad input and reports image failures"

# ── vm_require_tools ────────────────────────────────────────────────────────
TOOLS_BIN="$TEST_DIR/bin"
mkdir -p "$TOOLS_BIN"
CHMOD="$(command -v chmod)"
APT_RC=0
apt-get() {
  printf 'apt-get %s\n' "$*" >>"$LOG"
  [[ "$1" == install ]] || return 0
  ((APT_RC == 0)) || return "$APT_RC"
  local p t
  for p in "$@"; do
    case "$p" in
    xz-utils) printf '#!/bin/sh\n' >"$TOOLS_BIN/xz" && "$CHMOD" +x "$TOOLS_BIN/xz" ;;
    libguestfs-tools)
      for t in virt-customize virt-resize virt-filesystems; do
        printf '#!/bin/sh\n' >"$TOOLS_BIN/$t" && "$CHMOD" +x "$TOOLS_BIN/$t"
      done
      ;;
    esac
  done
}

with_path() {
  local saved="$PATH" rc=0
  PATH="$TOOLS_BIN"
  hash -r
  "$@" || rc=$?
  PATH="$saved"
  hash -r
  return "$rc"
}

reset_logs
with_path vm_require_tools xz virt-customize virt-resize || fail "installable tools"
assert_contains "$LOG" "apt-get install -y xz-utils libguestfs-tools"
[[ "$(grep -c 'apt-get install' "$LOG")" == 1 ]] || fail "one install for all missing tools"
ok "vm_require_tools installs each package once"

reset_logs
with_path vm_require_tools xz || fail "present tool"
[[ ! -s "$LOG" ]] || fail "nothing to install when the tool exists"
ok "vm_require_tools is a no-op when everything is present"

reset_logs
rm -f "$TOOLS_BIN/xz"
APT_RC=100
if with_path vm_require_tools xz; then fail "a failed install must fail"; fi
assert_contains "$ERRORS" "Could not install xz-utils"
APT_RC=0
reset_logs
if with_path vm_require_tools frobnicate; then fail "an unknown tool must fail"; fi
assert_contains "$ERRORS" "cannot be installed automatically: frobnicate"
[[ ! -s "$LOG" ]] || fail "unknown tools are not guessed into apt"
ok "vm_require_tools fails for failed installs and unknown tools"

# ── vm_wait_http and the closing block ──────────────────────────────────────
http_codes 000 502 302
vm_wait_http https://10.0.0.5:11443 30 --insecure || fail "302 counts as up"
http_codes 000 401
vm_wait_http https://10.0.0.5 30 || fail "401 counts as up"
http_codes 000 503 503 503 503 503 503
if vm_wait_http https://10.0.0.5 30; then fail "5xx is not up"; fi
ok "vm_wait_http: 2xx/3xx/401/403 up, 5xx and no answer not"

APP="Test App" VMID=100 HN=test-vm CORE_COUNT=2 RAM_SIZE=2048 DISK_SIZE=20G VM_IP=192.168.1.50 START_VM=yes
summary="$(vm_print_summary "Version=1.2.3" "Empty=" "URL=https://192.168.1.50:8443")"
for want in "Test App Summary:" "VM ID: 100" "Hostname: test-vm" "Resources: 2 vCPU, 2048 MiB RAM, 20G disk" \
  "State: running" "IP Address: 192.168.1.50" "Version: 1.2.3" "URL: https://192.168.1.50:8443"; do
  [[ "$summary" == *"$want"* ]] || fail "summary lacks <$want>: $summary"
done
[[ "$summary" != *"Empty:"* ]] || fail "empty rows are skipped"
START_VM=no VM_IP=""
summary="$(vm_print_summary)"
[[ "$summary" == *"State: stopped"* && "$summary" != *"IP Address"* ]] || fail "stopped VM summary: $summary"
steps="$(vm_next_steps "Open the console" "Detach the ISO")"
[[ "$steps" == *"Next Steps:"*"1. Open the console"*"2. Detach the ISO"* ]] || fail "next steps: $steps"
[[ -z "$(vm_next_steps)" ]] || fail "no steps, no heading"
ok "vm_print_summary and vm_next_steps"

reset_logs
post_update_to_api() { printf 'api %s %s\n' "$1" "$2" >>"$LOG"; }
msg_ok() { printf 'ok %s\n' "$*" >>"$LOG"; }
vm_finish "Created; installation continues in the VM" >/dev/null
assert_contains "$LOG" "api done none"
assert_contains "$LOG" "ok Created; installation continues in the VM"
ok "vm_finish reports done and the given message"

# ── Incus counterparts ──────────────────────────────────────────────────────
grep -qx '_incus_vm_source "vm/common.func"' "${COMMUNITY_SCRIPTS_CORE_DIR}/incus/vm-core.func" ||
  fail "incus/vm-core.func must load vm/common.func"
(
  eval "$(awk '/^_incus_vm_qm_only\(\)/,/^}/' "${COMMUNITY_SCRIPTS_CORE_DIR}/incus/vm-core.func")"
  eval "$(grep -E '^vm_(import_disk|start_vm|wait_guest_agent|guest_exec|wait_for_ip)\(\) \{ _incus_vm_qm_only' \
    "${COMMUNITY_SCRIPTS_CORE_DIR}/incus/vm-core.func")"
  for fn in vm_import_disk vm_start_vm vm_wait_guest_agent vm_guest_exec vm_wait_for_ip; do
    reset_logs
    rc=0
    "$fn" 100 x y || rc=$?
    assert_eq "$rc" 119 "$fn on Incus"
    assert_contains "$ERRORS" "only available on Proxmox VE"
  done
) || exit 1
ok "Incus loads the shared helpers and refuses the qm-only ones with exit 119"

printf '\n%d VM helper tests passed\n' "$passed"
