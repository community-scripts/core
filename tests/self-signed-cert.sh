#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v openssl >/dev/null 2>&1 || {
  echo "SKIP: no openssl"
  exit 0
}

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
# The helper writes to /etc/ssl/<app>; load it with that pointed at the test dir.
eval "$(awk '/^create_self_signed_cert\(\) \{/,/^}/' "$CORE_DIR/lib/system.func" | sed "s#/etc/ssl#${TEST_DIR}#g")"
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

# shellcheck disable=SC2034  # read by the eval'd helper
STD=""
msg_error() { echo "error: $*" >&2; }
ensure_dependencies() { :; }
crt="$TEST_DIR/demo/demo.crt"
days_left() { local d=$((($(date -d "$(openssl x509 -enddate -noout -in "$crt" | cut -d= -f2)" +%s) - $(date +%s)) / 86400)); ((d >= 824 && d <= 825)) && echo 825 || echo "$d"; }
serial() { openssl x509 -serial -noout -in "$crt"; }

create_self_signed_cert demo
check "a new certificate is valid for 825 days" "825" "$(days_left)"

before="$(serial)"
create_self_signed_cert demo
check "a valid certificate is kept" "$before" "$(serial)"

# Replace it with one that runs out in 10 days.
openssl req -new -newkey rsa:2048 -days 10 -nodes -x509 -subj "/CN=old" \
  -keyout "$TEST_DIR/demo/demo.key" -out "$crt" >/dev/null 2>&1
create_self_signed_cert demo
check "an expiring certificate is renewed" "825" "$(days_left)"
check "and the key stays private" "600" "$(stat -c %a "$TEST_DIR/demo/demo.key")"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
