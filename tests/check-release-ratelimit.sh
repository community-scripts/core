#!/usr/bin/env bash
# A rate-limited GitHub API no longer stops the update check: the release is
# read from github.com, as the deploy path already does.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^_FORGE_JQ_VKEY_DEF=/,/^_FORGE_JQ_VKEY=/p' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^_forge_(descriptor|strip_v|is_current|highest_version|same_shape|stable_filter|http_get|designated_release)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"
eval "$(awk '/^(check_for_release|_forge_previous_version)[(][)] [{]/,/^}/' "$CORE_DIR/lib/forge.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
LOG="$TEST_DIR/log"
passed=0 failed=0

# jq on Windows prints CRLF; mapfile -t keeps the CR and the tag compare is exact.
jq() { command jq "$@" | tr -d '\r'; }
msg_info() { :; }
msg_ok() { :; }
msg_warn() { echo "warn: $*" >>"$LOG"; }
msg_error() { echo "error: $*" >>"$LOG"; }
ensure_dependencies() { :; }
getent() { return 0; }
sleep() { :; }
_github_token_from_vars() { :; }
_github_token_rejected() { return 1; }
_github_token_refused_by_org() { return 1; }

# Every API call is refused the way each forge refuses an exhausted limit.
_forge_curl() {
  local out="$1" url="${*: -1}"
  echo '{"message":"API rate limit exceeded"}' >"$out"
  case "$url" in
  https://api.github.com/*) echo 403 ;;
  *) echo 429 ;;
  esac
}
# github.com answers for the latest release and for any named tag.
_github_release_noapi() {
  echo "noapi $2" >>"$LOG"
  [[ "${NOAPI:-up}" == up ]] || return 1
  local tag="$2"
  [[ "$tag" == latest ]] && tag="v2.16.0"
  printf '{"tag_name":"%s","name":"%s","draft":false,"prerelease":false,"body":"","assets":[]}' "$tag" "$tag" >"$3"
}

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    sed 's/^/    /' "$LOG" >&2
    failed=$((failed + 1))
  fi
}
# forge, installed version, then the optional pin arguments; sets RC
check() {
  local forge="$1" installed="$2"
  shift 2
  : >"$LOG"
  rm -f "$HOME/.app" "$HOME/.app.pending"
  echo "$installed" >"$HOME/.app"
  CHECK_UPDATE_RELEASE=""
  RC=0
  check_for_release "$forge" app owner/app "$@" >/dev/null 2>&1 || RC=$?
}
logged() { grep -c "^$1" "$LOG"; }

check github 2.15.1
expect "newer release: update offered" "0 v2.16.0" "$RC $CHECK_UPDATE_RELEASE"
expect "newer release: says where it read it" "1" "$(logged 'warn: GitHub API rate limit reached; read the release from github.com')"
expect "newer release: no error" "0" "$(logged error)"

check github 2.16.0
expect "current release: no update" "1" "$RC"

check github 2.14.0 v2.15.1
expect "pinned tag: update to the pin" "0 v2.15.1" "$RC $CHECK_UPDATE_RELEASE"
expect "pinned tag: github.com asked for the pin" "1" "$(logged 'noapi v2.15.1')"

NOAPI=down check github 2.15.1
expect "github.com down too: error as before" "22" "$RC"
expect "github.com down too: names the limit once" "1" "$(logged 'error: github: rate limit reached')"

check github 2.15.1 "" "" "app-"
expect "tag prefix: no fallback" "22 0" "$RC $(logged noapi)"

GH_INCLUDE_PRERELEASE=1 check github 2.15.1
expect "prereleases wanted: no fallback" "22 0" "$RC $(logged noapi)"

check gitlab 2.15.1
expect "gitlab: unchanged" "22 0 1" "$RC $(logged noapi) $(logged 'error: gitlab: rate limit reached')"

echo "${passed} passed, ${failed} failed"
[[ "$failed" -eq 0 ]]
