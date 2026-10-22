#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^(_incus_parse_size_to_bytes|incus_storage_pool_free_gb)[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"

passed=0 failed=0
export INCUS_REMOTE=incusos
# A ZFS pool as Incus reports it: total and used only, integers with --bytes.
incus() {
  case "$*" in
  "storage info --bytes local")
    [[ "${MOCK_BYTES:-yes}" == "yes" ]] && printf 'info:\n  driver: zfs\n  name: local\n  space used: 238747648\n  total space: 88900000000\nused by: {}\n'
    ;;
  "storage info local")
    printf 'info:\n  driver: zfs\n  name: local\n  space used: 227.68MiB\n  total space: 82.80GiB\nused by: {}\n'
    ;;
  "storage get local source") echo "/var/lib/incus/storage-pools/local" ;;
  esac
}

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

expect "free space comes from the byte counts" 82 "$(incus_storage_pool_free_gb local)"
expect "without --bytes the human sizes still work" 82 "$(MOCK_BYTES=no incus_storage_pool_free_gb local)"
expect "GiB parses" 88905823027 "$(_incus_parse_size_to_bytes 82.80GiB)"
expect "MiB parses" 238739783 "$(_incus_parse_size_to_bytes 227.68MiB)"
expect "a plain number is bytes" 4096 "$(_incus_parse_size_to_bytes 4096)"
expect "nonsense is rejected" 1 "$(_incus_parse_size_to_bytes bogus >/dev/null 2>&1; echo $?)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
