#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^setup_ruby\(\) \{/,/^}/' "$CORE_DIR/lib/runtime.func")"

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

# shellcheck disable=SC2034  # read by setup_ruby
STD=""
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
ensure_apt_working() { :; }
apt-cache() { echo found; }
apt() { :; }
cache_installed_version() { :; }

# rbenv and ruby-build are already there; the fake rbenv records how install runs.
export HOME="$TEST_DIR/home"
RBENV="$HOME/.rbenv"
mkdir -p "$RBENV/bin" "$RBENV/plugins/ruby-build/share/ruby-build"
: >"$RBENV/plugins/ruby-build/share/ruby-build/3.4.7"
cat >"$RBENV/bin/rbenv" <<EOF
#!/usr/bin/env bash
case "\$1" in
install)
  {
    echo "tmpdir=\$TMPDIR"
    echo "opts=\$RUBY_CONFIGURE_OPTS"
    [[ -d "\$TMPDIR" ]] && echo "tmpdir-exists=yes"
  } >"$TEST_DIR/install.log"
  exit "\${FAKE_INSTALL_RC:-0}"
  ;;
global) [[ -n "\${2:-}" ]] && exit 0 ;;
esac
exit 0
EOF
chmod +x "$RBENV/bin/rbenv"

run() {
  : >"$TEST_DIR/install.log"
  (RUBY_VERSION=3.4.7 RUBY_INSTALL_RAILS=false setup_ruby >/dev/null 2>&1)
}
logged() { sed -n "s/^$1=//p" "$TEST_DIR/install.log"; }

run
check "setup succeeds" 0 "$?"
check "the build tree is on disk, not in tmpfs /tmp" "/var/tmp" "$(dirname "$(logged tmpdir)")"
check "the build directory exists during the build" "yes" "$(logged tmpdir-exists)"
check "the build directory is removed afterwards" "no" "$([[ -e "$(logged tmpdir)" ]] && echo yes || echo no)"
check "docs are not built" "--disable-install-doc " "$(logged opts)"

RUBY_CONFIGURE_OPTS="--with-jemalloc" run
check "a caller's configure options are kept" "--disable-install-doc --with-jemalloc" "$(logged opts)"

FAKE_INSTALL_RC=1 run
check "a failed build fails the setup" 150 "$?"
check "a failed build keeps its log for inspection" "yes" "$([[ -d "$(logged tmpdir)" ]] && echo yes || echo no)"

echo "${passed} passed, ${failed} failed"
((failed == 0))
