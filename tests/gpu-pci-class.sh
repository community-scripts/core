#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERN='^[^ ]+ (VGA compatible|XGA compatible|3D|Display) controller[ :]'
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

for f in lib/hwaccel.func api/sysinfo.func pve/backend.func incus/backend.func; do
  check "$f filters lspci on the class field" 1 "$(grep -F "lspci" "$CORE_DIR/$f" | grep -cF "grep -E '$PATTERN'")"
done

# From issue #217 and telemetry gpu_model values; the slot says what each is.
lines=(
  "02:00.0 USB controller: Advanced Micro Devices, Inc. [AMD] Device 43d0 (rev 01)"
  "03:00.0 Non-Volatile memory controller: Sandisk Corp SanDisk Ultra 3D / WD PC SN530, IX SN530, Blue SN550 NVMe SSD (rev 01)"
  "04:00.0 Non-Volatile memory controller: Realtek Semiconductor Co., Ltd. RTS5763DL x2 NVMe SSD Controller (rev 01)"
  "00:03.0 PCI bridge: Intel Corporation Xeon E5/Core i7 IIO PCI Express Root Port 3d (rev 07)"
  "0b:00.1 Audio device: NVIDIA Corporation GA104 High Definition Audio Controller (rev a1)"
  "0b:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3070] (rev a1)"
  "0e:00.0 VGA compatible controller: Intel Corporation Battlemage G21 [Intel Graphics]"
  "01:00.0 3D controller: NVIDIA Corporation GP104GL [Tesla P4] (rev a1)"
  "00:02.0 Display controller: Intel Corporation HD Graphics 630 (rev 04)"
)
check "plain lspci: only display controllers" "0b:00.0 0e:00.0 01:00.0 00:02.0" \
  "$(printf '%s\n' "${lines[@]}" | grep -E "$PATTERN" | awk '{print $1}' | xargs)"

nn=(
  "02:00.0 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Device [1022:43d0] (rev 01)"
  "0b:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA104 [GeForce RTX 3070] [10de:2484] (rev a1)"
  "0000:0e:00.0 VGA compatible controller [0300]: Intel Corporation Battlemage G21 [Intel Graphics] [8086:e20b]"
)
check "lspci -nn and -D: only display controllers" "0b:00.0 0000:0e:00.0" \
  "$(printf '%s\n' "${nn[@]}" | grep -E "$PATTERN" | awk '{print $1}' | xargs)"

eval "$(awk '/^_gpu_type[(][)] [{]/,/^}/' "$CORE_DIR/lib/hwaccel.func")"
check "Battlemage by ID, named" INTEL_ARC "$(_gpu_type 8086:e20b 'Intel Corporation Battlemage G21 [Intel Graphics]')"
check "Battlemage by ID, unnamed" INTEL_ARC "$(_gpu_type 8086:e212 'Intel Corporation Device e212')"
check "Alchemist by ID" INTEL_ARC "$(_gpu_type 8086:56a0 'Intel Corporation Device 56a0')"
check "integrated Arc by name" INTEL_ARC "$(_gpu_type 8086:7d55 'Intel Corporation Meteor Lake-P [Intel Arc Graphics]')"
check "UHD is Gen9+" INTEL_GEN9+ "$(_gpu_type 8086:3e92 'Intel Corporation CoffeeLake-S GT2 [UHD Graphics 630]')"
check "HD 530 is Gen9+" INTEL_GEN9+ "$(_gpu_type 8086:1912 'Intel Corporation HD Graphics 530 (rev 06)')"
check "HD 4000 is legacy" INTEL_LEGACY "$(_gpu_type 8086:0162 'Intel Corporation IvyBridge GT2 [HD Graphics 4000]')"
check "an unknown Intel card stays generic" INTEL "$(_gpu_type 8086:a7a0 'Intel Corporation Device a7a0')"
check "NVIDIA by vendor, unnamed" NVIDIA "$(_gpu_type 10de:2484 'NVIDIA Corporation Device 2484')"
check "AMD by vendor" AMD "$(_gpu_type 1002:73bf 'Advanced Micro Devices, Inc. [AMD/ATI] Navi 21')"
check "another vendor is no GPU we set up" "" "$(_gpu_type 1a03:2000 'ASPEED Technology, Inc. ASPEED Graphics Family')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
