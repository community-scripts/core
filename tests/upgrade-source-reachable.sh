#!/usr/bin/env bash
# An upgrade purged the installed Node.js or database server first and fetched
# the new version's repository key second; with that host out of reach the
# container was left without either.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_upgrade_source_reachable[(][)] [{]/,/^}/' "$CORE_DIR/lib/system.func")"

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

msg_error() { echo "$*" >>"$TEST_DIR/errors"; }
curl() { echo "${*: -1}" >>"$TEST_DIR/urls"; return "$CURL_RC"; }

CURL_RC=0
_upgrade_source_reachable "MariaDB" "https://mariadb.org/key.asc"
expect "a reachable source lets the upgrade go on" 0 "$?"
expect "without a message" 0 "$(wc -l <"$TEST_DIR/errors" 2>/dev/null || echo 0)"

CURL_RC=7
_upgrade_source_reachable "MariaDB" "https://mariadb.org/key.asc"
expect "an unreachable source stops it" 1 "$?"
expect "and says the installed version stays" \
  "MariaDB upgrade not started: https://mariadb.org/key.asc is out of reach, the installed version stays" \
  "$(cat "$TEST_DIR/errors")"
expect "the key itself is what gets fetched" "https://mariadb.org/key.asc" "$(tail -n1 "$TEST_DIR/urls")"

# In every upgrade path the check comes before the purge.
order() {
  awk -v fn="$2" -v tool="$3" '
    $0 ~ "^" fn "[(][)] [{]" { inside = 1 }
    inside && /^}/ { exit }
    inside && /_upgrade_source_reachable "/ && !check { check = NR }
    inside && $0 ~ "remove_old_tool_version \"" tool "\"" && !purge { purge = NR }
    END { print (check && purge && check < purge) ? "check first" : "check=" check " purge=" purge }
  ' "$CORE_DIR/lib/$1"
}
expect "Node.js" "check first" "$(order runtime.func setup_nodejs nodejs)"
expect "MariaDB" "check first" "$(order db.func setup_mariadb mariadb)"
expect "MySQL" "check first" "$(order db.func setup_mysql mysql)"
expect "MongoDB" "check first" "$(order db.func setup_mongodb mongodb)"
expect "ClickHouse" "check first" "$(order db.func setup_clickhouse clickhouse)"

echo "passed=${passed} failed=${failed}"
((failed == 0))
