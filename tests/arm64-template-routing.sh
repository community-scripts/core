#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../ui/defaults.func
source "$repo_root/ui/defaults.func"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

msg_warn() { :; }
msg_ok() { :; }

MOCK_ARCH="arm64"
dpkg() {
  [[ "${1:-}" == "--print-architecture" ]] || return 1
  printf '%s\n' "$MOCK_ARCH"
}

_pveam_available() {
  cat <<'EOF'
system          debian-13-standard_13.6-1_amd64.tar.zst
system          debian-13-standard_13.6-1_arm64.tar.zst
system          ubuntu-24.04-standard_24.04-1_arm64.tar.zst
EOF
}

pveam() {
  if [[ "${1:-}" == "list" ]]; then
    printf '%s\n' 'local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst'
    return 0
  fi
  return 1
}

# Without a PVE backend hook, ARM64 version resolution remains unchanged for
# Incus and any other platform-specific template source.
var_os="debian"
var_version="12"
export var_os var_version
resolve_os_version
[[ "$var_version" == "12" ]] || fail "Non-PVE ARM64 version resolution changed"

# shellcheck source=../pve/backend.func
source "$repo_root/pve/backend.func"

if _use_custom_arm64_template arm64 debian; then
  fail "Debian ARM64 must use the official pveam catalog"
fi
if ! _use_custom_arm64_template arm64 ubuntu; then
  fail "Ubuntu ARM64 must retain the custom-template fallback"
fi
if ! _use_custom_arm64_template arm64 alpine; then
  fail "Alpine ARM64 must retain the custom-template fallback"
fi
if _use_custom_arm64_template amd64 debian; then
  fail "AMD64 must not use the custom ARM64 path"
fi

mapfile -t templates < <(_list_templates "debian-13" "-standard_")
[[ "${#templates[@]}" -eq 1 ]] || fail "Expected exactly one Debian 13 ARM64 template"
[[ "${templates[0]}" == "debian-13-standard_13.6-1_arm64.tar.zst" ]] ||
  fail "Template discovery selected the wrong architecture"

mapfile -t filtered < <(
  printf '%s\n' \
    'debian-13-standard_13.6-1_amd64.tar.zst' \
    'debian-13-standard_13.6-1_arm64.tar.zst' \
    'debian-12-standard_12.12-1_amd64.tar.gz' \
    'debian-12-standard_12.12-1_arm64.tar.xz' |
    _filter_templates_by_arch arm64
)
[[ "${#filtered[@]}" -eq 2 ]] || fail "ARM64 fallback filtering returned the wrong number of templates"
[[ "${filtered[0]}" == *'_arm64.tar.zst' && "${filtered[1]}" == *'_arm64.tar.xz' ]] ||
  fail "ARM64 fallback filtering selected another architecture"

# Debian ARM64 now resolves through pveam. An amd64-only local Debian 12
# template must not prevent selecting the available ARM64 Debian 13 template.
export PHS_SILENT=1
export PVEVERSION="test"
export TEMPLATE_STORAGE="local"
var_os="debian"
var_version="12"
resolve_os_version
[[ "$var_version" == "13" ]] || fail "Debian ARM64 did not resolve through the architecture-filtered catalog"

# Non-Debian ARM64 distributions continue to use their custom template source.
var_os="ubuntu"
var_version="22.04"
resolve_os_version
[[ "$var_version" == "22.04" ]] || fail "Ubuntu ARM64 unexpectedly used the pveam catalog"

# AMD64 keeps the existing pveam resolution behavior.
MOCK_ARCH="amd64"
var_os="debian"
var_version="12"
resolve_os_version
[[ "$var_version" == "12" ]] || fail "AMD64 local template resolution changed"

if grep -qF 'community-scripts/debian-arm64-lxc' "$repo_root/pve/backend.func"; then
  fail "The removed Debian ARM64 repository reference returned"
fi

printf 'ARM64 template routing checks passed\n'
