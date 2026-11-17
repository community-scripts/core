#!/usr/bin/env bash
# What a failing command prints goes into the telemetry trace through
# _tm_clean_log. Credentials and addresses in it are masked; ordinary output
# stays as it was. Runs with GNU and BusyBox sed alike.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$CORE_DIR/api/errorlog.func"
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

# input <TAB> expected; "=" means unchanged
while IFS=$'\t' read -r input want; do
  [[ -n "$input" ]] || continue
  [[ "$want" == "=" ]] && want="$input"
  expect "$input" "$want" "$(printf '%s\n' "$input" | _tm_clean_log)"
done <<'EOF'
error="Get \"https://ci-user:SECRET_A1@git.example.net/api/v1/ping\": dial tcp	error="Get \"https://***@git.example.net/api/v1/ping\": dial tcp
fatal: unable to access 'https://x-access-token:SECRET_A2@github.com/org/repo.git/'	fatal: unable to access 'https://***@github.com/org/repo.git/'
curl: (22) git+https://SECRET_A3@example.com/x	curl: (22) git+https://***@example.com/x
DB_PASS=SECRET_B1	DB_PASS=***
+(/opt/x.sh:12): main(): MYSQL_PASSWORD=SECRET_B2 ./run	+(/opt/x.sh:12): main(): MYSQL_PASSWORD=*** ./run
Admin password: SECRET_B3	Admin password: ***
{"password":"SECRET_B4","user":"admin"}	{"password":"***","user":"admin"}
{\"api_key\":\"SECRET_B5\"}	{\"api_key\":\"***\"}
--db-password=SECRET_B6 --dbpass=SECRET_B7 --name=glpi	--db-password=*** --dbpass=*** --name=glpi
GET /cb?access_token=SECRET_B8&state=1	GET /cb?access_token=***&state=1
client_secret = 'SECRET_B9'	client_secret = '***'
X-Api-Key: SECRET_B10	X-Api-Key: ***
APIKEY=SECRET_B11	APIKEY=***
> Authorization: Bearer SECRET_B12	> Authorization: Bearer ***
Proxy-Authorization: Basic SECRET_B13	Proxy-Authorization: Basic ***
psql:1: CREATE USER app WITH PASSWORD 'SECRET_C1';	psql:1: CREATE USER app WITH PASSWORD '***';
CREATE USER 'app'@'localhost' IDENTIFIED BY 'SECRET_C2';	CREATE USER 'app'@'localhost' IDENTIFIED BY '***';
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY "SECRET_C3";	ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY "***";
contact alice.smith+ci@example.net for access	contact <email> for access
php artisan setup --email=admin@example.org --force	php artisan setup --email=<email> --force
resolved via 2001:db8:77::5 (link fe80::1%eth0, loopback [::1]:8080)	resolved via <ipv6> (link <ipv6>%eth0, loopback [<ipv6>]:8080)
full 2001:0db8:0000:0000:0000:ff00:0042:8329 here	full <ipv6> here
link/ether bc:24:11:aa:bb:cc brd ff:ff:ff:ff:ff:ff	link/ether <mac> brd <mac>
mkdir -p /opt/app/data	=
cp -p /etc/app.conf /opt/app/	=
ssh-keygen -t ed25519 -P "" -f /root/.ssh/id	=
htpasswd -b -B -c /etc/zot/htpasswd admin	=
Tests passed: 12, failed: 0	=
Passing the --frozen-lockfile flag	=
FATAL:  password authentication failed for user "app"	=
Job for postgresql@17-main.service failed because the control process exited with error code.	=
getty@tty1.service: Succeeded.	=
npm error notarget No matching version found for @types/node@99.0.0.	=
 ERR_PNPM_FETCH_404  GET https://registry.npmjs.org/@scope%2fpkg: Not Found - 404	=
[2026-01-01 10:00:06] [INFO] Setting up Demo	=
error[E0433]: failed to resolve: use of undeclared crate or module `serde::de::Deserialize`	=
thread 'main' panicked at src/main.rs:10:5	=
dpkg: dependency problems prevent configuration of foo: depends on libc6 (>= 2:2.38)	=
Error: Cannot find module '/opt/app/dist/index.js'	=
token	=
EOF

expect "noise lines are still dropped" "" "$(printf '%s\n' 'Setting up libssl3t64:amd64 (3.5.1-1) ...' 'Get:1 http://deb.debian.org/debian trixie InRelease [140 kB]' | _tm_clean_log)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
