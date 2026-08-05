#!/usr/bin/env python3
"""Generate figlet headers for every community script into headers/<APP_TYPE>/.

Headers are derived from a script's APP= line, so this is the only place they
should ever be written. The layout is keyed by APP_TYPE rather than by the
directory a script happens to live in, because get_header() resolves
headers/${APP_TYPE}/${slug} -- and APP_TYPE does not always match the folder
(scripts under tools/addon/ declare APP_TYPE="addon").

Usage: generate-headers.py <script-repo> [<script-repo> ...]
Earlier repositories win when the same app appears more than once.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

APP_RE = re.compile(r'^APP="([^"]+)"', re.M)
TYPE_RE = re.compile(r'^APP_TYPE="?([a-z]+)"?', re.M)

# Where scripts live in a script repo, and whether to recurse.
SCRIPT_DIRS = (("ct", "*.sh"), ("tools", "**/*.sh"), ("vm", "*.sh"))

# ct/, vm/ and addon/ scripts are platform-agnostic: one script, one header,
# both hosts. Host tools are not -- tools/pve/ never runs on Incus and
# tools/incus/ never on Proxmox VE -- so their headers are kept apart, keyed by
# the platform their source directory already declares.
TOOL_PLATFORMS = ("pve", "incus")

OUT = Path("headers")


def slug(app: str) -> str:
    """Match get_header(): APP lowercased with spaces removed."""
    return app.lower().replace(" ", "")


def figlet(app: str) -> str | None:
    try:
        out = subprocess.run(
            ["figlet", "-w", "500", "-f", "slant", app],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return out if out.strip() else None


def main(repos: list[str]) -> int:
    if not repos:
        print("usage: generate-headers.py <script-repo> [...]", file=sys.stderr)
        return 2

    written: dict[tuple[str, str], str] = {}
    skipped: list[str] = []

    for repo in repos:
        root = Path(repo)
        for sub, pattern in SCRIPT_DIRS:
            for script in sorted((root / sub).glob(pattern)):
                if not script.is_file():
                    continue
                text = script.read_text(encoding="utf-8", errors="replace")
                m = APP_RE.search(text)
                if not m:
                    continue
                app = m.group(1).strip()
                # Some scripts derive APP from a variable; there is nothing to
                # render and the slug would be literal shell syntax.
                if "$" in app or not app:
                    skipped.append(f"{repo}/{script.relative_to(root)}: APP={app!r}")
                    continue
                t = TYPE_RE.search(text)
                app_type = t.group(1) if t else "ct"
                # tools/<platform>/x.sh -> headers/tools/<platform>/
                if app_type == "tools":
                    parts = script.relative_to(root).parts
                    platform = parts[1] if len(parts) > 2 and parts[1] in TOOL_PLATFORMS else None
                    if platform is None:
                        skipped.append(
                            f"{repo}/{script.relative_to(root)}: APP_TYPE=tools "
                            f"outside tools/{{{'|'.join(TOOL_PLATFORMS)}}}/"
                        )
                        continue
                    app_type = f"tools/{platform}"
                key = (app_type, slug(app))
                if key in written:
                    continue
                art = figlet(app)
                if art is None:
                    skipped.append(f"{repo}/{script.relative_to(root)}: figlet failed")
                    continue
                written[key] = art

    # Rewrite the tree so removed apps do not leave orphans behind.
    for stale in sorted(OUT.rglob("*")):
        if stale.is_file():
            stale.unlink()
    for (app_type, name), art in sorted(written.items()):
        d = OUT / app_type
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_text(art, encoding="utf-8", newline="\n")

    counts = Counter(t for t, _ in written)
    print("generated:")
    for t, n in sorted(counts.items()):
        print(f"  headers/{t:<8} {n}")
    print(f"  total     {len(written)}")

    if skipped:
        print(f"\nskipped {len(skipped)}:")
        for s in skipped:
            print("  ", s)

    if not written:
        print("::error::no headers generated - script layout probably changed")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
