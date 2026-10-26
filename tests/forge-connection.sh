#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_forge_explain_failure\(\) \{/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
LOG="$TEST_DIR/log"
passed=0 failed=0

msg_error() { echo "$*" >>"$LOG"; }
# The probe fails like the real transfer did; the -4 probe answers per MOCK_V4.
curl() {
  if [[ " $* " == *" -4 "* ]]; then
    [[ "${MOCK_V4:-000}" != "000" ]] || return 7
    printf '%s' "$MOCK_V4"
    return 0
  fi
  [[ -n "${MOCK_MSG:-}" ]] && echo "curl: (${MOCK_RC}) ${MOCK_MSG}" >&2
  return "${MOCK_RC:-0}"
}
ip() { [[ -n "${MOCK_V6:-}" ]] && echo "    inet6 2001:db8::1/64 scope global"; }

run() {
  : >"$LOG"
  _forge_explain_failure api.github.com
}
expect() {
  if grep -qF -- "$2" "$LOG"; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: missing <$2>" >&2
    sed 's/^/    /' "$LOG" >&2
    failed=$((failed + 1))
  fi
}

MOCK_RC=6 MOCK_MSG="Could not resolve host: api.github.com" run
expect "curl message is shown" "curl: Could not resolve host: api.github.com"
expect "dns failure points at the resolver" "does not resolve"

MOCK_RC=7 MOCK_MSG="Failed to connect" MOCK_V4=200 MOCK_V6=1 run
expect "v4 works, v6 configured: blames the v6 route" "IPv6 does not"

MOCK_RC=7 MOCK_MSG="Failed to connect" MOCK_V4=200 run
expect "v4 works, no v6 address: transient" "answered an IPv4 probe"

MOCK_RC=7 MOCK_MSG="Failed to connect" MOCK_V4=000 run
expect "nothing reachable: no route" "No route to api.github.com"

MOCK_RC=28 MOCK_MSG="Connection timed out" MOCK_V4=000 run
expect "timeout" "timed out"

MOCK_RC=35 MOCK_MSG="SSL certificate problem" run
expect "tls" "TLS handshake"

MOCK_RC=56 MOCK_MSG="Recv failure: Connection reset by peer" run
expect "reset" "was reset"

MOCK_RC=0 run
expect "probe succeeds: transient" "answers now"

MOCK_RC=99 MOCK_MSG="something odd" run
expect "unknown code falls back to curl -v" "curl -v https://api.github.com/"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
