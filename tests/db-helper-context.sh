#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^random_password\(\) \{/,/^}/' "$CORE_DIR/core/core.func")"
eval "$(awk '/^setup_(postgresql|mariadb|mysql)_db\(\) \{/,/^}/' "$CORE_DIR/lib/db.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
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

# shellcheck disable=SC2034  # read by the eval'd helpers
STD=""
msg_info() { :; }
msg_ok() { :; }
msg_error() { echo "error: $*" >&2; }
sudo() { :; }
mariadb() { :; }
mysql() { :; }
systemctl() { :; }

# An addon calls these without the install context's APPLICATION; set -u then
# ended the run with "APPLICATION: unbound variable".
run() {
  local home="$TEST_DIR/$1"
  mkdir -p "$home"
  (
    set -u
    HOME="$home"
    unset APPLICATION
    APP="pgAdmin"
    PG_DB_NAME=appdb PG_DB_USER=appuser
    MARIADB_DB_NAME=appdb MARIADB_DB_USER=appuser
    MYSQL_DB_NAME=appdb MYSQL_DB_USER=appuser
    "setup_$1_db" >/dev/null 2>&1 || exit 1
    case "$1" in
    postgresql) pass="$PG_DB_PASS" ;;
    mariadb) pass="$MARIADB_DB_PASS" ;;
    mysql) pass="$MYSQL_DB_PASS" ;;
    esac
    printf '%s %s %s' "$([[ "$pass" =~ ^[A-Za-z0-9]{24}$ ]] && echo alnum24 || echo "bad:$pass")" "$(ls "$home")" "$(stat -c %a "$home"/*.creds)"
  ) || echo "aborted"
}

# The creds file holds the database password; it was left world-readable (644).
for db in postgresql mariadb mysql; do
  check "$db: runs without APPLICATION, alphanumeric password, creds named after APP and private" "alnum24 pgadmin.creds 600" "$(umask 022; run "$db")"
done

# Scripts suppress the file with PG_DB_CREDS_FILE=/dev/null; chmod 600 on it would
# lock every non-root process out of /dev/null.
devnull_chmods() {
  (
    chmod() { echo "chmod $*" >>"$TEST_DIR/chmod.log"; }
    HOME="$TEST_DIR"
    APP="demo"
    PG_DB_NAME=appdb PG_DB_USER=appuser PG_DB_CREDS_FILE=/dev/null setup_postgresql_db >/dev/null 2>&1
  )
  grep -c '/dev/null' "$TEST_DIR/chmod.log" 2>/dev/null || echo 0
}
check "PG_DB_CREDS_FILE=/dev/null is never chmodded" "0" "$(devnull_chmods)"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
