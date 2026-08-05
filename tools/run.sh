#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/core/raw/main/LICENSE
#
# Remote fork/branch runner.
#
# The engine (core) and the scripts (ProxmoxVE / ProxmoxVED / Incus) live in
# separate repositories and resolve independently, so this sets both bases and
# then runs a script from the script base. Either can point at a fork.
#
# Usage:
#   curl -fsSL <core-base>/tools/run.sh | bash -s -- <script-base> <script> [core-base]
#
# Production scripts against a core fork:
#   CORE=https://raw.githubusercontent.com/YOU/core/my-branch
#   SCRIPTS=https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main
#   curl -fsSL "$CORE/tools/run.sh" | bash -s -- "$SCRIPTS" ct/debian.sh "$CORE"
#
# A script fork against production core:
#   SCRIPTS=https://raw.githubusercontent.com/YOU/ProxmoxVE/my-branch
#   curl -fsSL https://raw.githubusercontent.com/community-scripts/core/main/tools/run.sh |
#     bash -s -- "$SCRIPTS" ct/debian.sh
#
# Local checkout (preferred, zero config): just run the script.
#   bash ct/debian.sh
# Point it at a core checkout elsewhere with COMMUNITY_SCRIPTS_CORE_DIR.
#
set -euo pipefail

SCRIPTS_BASE="${1:-}"
SCRIPT="${2:-}"
CORE_BASE="${3:-${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}}"

if [[ -z "$SCRIPTS_BASE" || -z "$SCRIPT" ]]; then
  cat >&2 <<'USAGE'
Usage: curl -fsSL <core-base>/tools/run.sh | bash -s -- <script-base> <script> [core-base]

  script-base  raw base of the script repo  e.g. https://raw.githubusercontent.com/YOU/ProxmoxVE/branch
  script       path within that repo         e.g. ct/debian.sh
  core-base    raw base of the engine repo   default: community-scripts/core@main
                                             (or $COMMUNITY_SCRIPTS_CORE_URL)
USAGE
  exit 2
fi

SCRIPTS_BASE="${SCRIPTS_BASE%/}"
CORE_BASE="${CORE_BASE%/}"
SCRIPT="${SCRIPT#./}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

export COMMUNITY_SCRIPTS_URL="$SCRIPTS_BASE"
export COMMUNITY_SCRIPTS_CORE_URL="$CORE_BASE"

echo "Engine  : ${COMMUNITY_SCRIPTS_CORE_URL}" >&2
echo "Scripts : ${COMMUNITY_SCRIPTS_URL}" >&2
echo "Running : ${SCRIPT}" >&2
bash -c "$(curl -fsSL "${COMMUNITY_SCRIPTS_URL}/${SCRIPT}")"
