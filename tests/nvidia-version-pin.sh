#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for fn in _cuda_pick_version _nvidia_version_pin _nvidia_apt_pins; do
  eval "$(awk "/^${fn}[(][)] [{]/,/^}/" "$CORE_DIR/lib/hwaccel.func")"
done
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

# Newest first, like madison.
apt-cache() {
  local v list
  case "$2" in
  libcuda1) list="620.70.06-1 595.112.07-1 595.71.05-1 590.48.01-1" ;;
  libnvidia-compute) list="620.70.06-1ubuntu1 595.112.07-1ubuntu1" ;;
  libnvidia-compute-595) list="595.99.02-0ubuntu0.24.04.1" ;;
  *) return 0 ;;
  esac
  for v in $list; do
    printf ' %s | %s | https://developer.download.nvidia.com/compute/cuda/repos  Packages\n' "$2" "$v"
  done
}

check "the host's exact release wins" 595.112.07-1 "$(_cuda_pick_version 595.112.07)"
check "a mid-series host is not handed a newer release" 595.71.05-1 "$(_cuda_pick_version 595.71.05)"
check "a missing release falls back to the series" 595.112.07-1 "$(_cuda_pick_version 595.80.01)"
check "another series is never taken" "" "$(_cuda_pick_version 580.126.09)"
check "Ubuntu: NVIDIA's package has the host's release" 595.112.07-1ubuntu1 "$(_cuda_pick_version 595.112.07 libnvidia-compute)"
check "Ubuntu: the archive's package only has its own" 595.99.02-0ubuntu0.24.04.1 "$(_cuda_pick_version 595.112.07 libnvidia-compute-595)"

pins="$(_nvidia_apt_pins 595.112.07-1)"
check "apt reads the version stanza first" "Pin: version 595.112.07-1" "$(grep -m1 '^Pin:' <<<"$pins")"
check "the stanzas are separated by a blank line" 1 "$(grep -c '^$' <<<"$pins")"

priority() { awk -v pin="$2" '/^Pin:/ {hit = index($0, pin)} hit && /^Pin-Priority:/ {print $2; exit}' <<<"$1"; }
version_prio="$(priority "$pins" "Pin: version")"
origin_prio="$(priority "$pins" "Pin: origin")"
check "the version pin outranks the origin pin" yes "$([[ "$version_prio" -gt "$origin_prio" ]] && echo yes || echo no)"

globs="$(grep -m1 '^Package:' <<<"$pins" | cut -d' ' -f2-)"
covered() {
  local glob
  for glob in $globs; do
    # shellcheck disable=SC2053
    [[ "$1" == $glob ]] && return 0
  done
  return 1
}
uncovered=()
set -f
for pkg in libcuda1 libnvcuvid1 libnvidia-encode1 libnvidia-ml1 libnvidia-ptxjitcompiler1 libnvidia-gpucomp libnvidia-pkcs11-openssl3 libnvidia-compute nvidia-persistenced; do
  covered "$pkg" || uncovered+=("$pkg")
done
set +f
check "the version pin covers the whole dependency chain" "" "${uncovered[*]}"

check "without a version only the origin pin is written" "Pin: origin developer.download.nvidia.com" "$(_nvidia_apt_pins | grep '^Pin:')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
