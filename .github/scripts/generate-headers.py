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

# A header is platform-specific when the script sits under a pve/ or incus/ path
# segment -- tools/pve/, tools/incus/, and in future vm/incus/ or addon/incus/.
# Everything else is agnostic: one banner, both hosts. The rule is uniform
# across types, so a repo opts in purely by where it puts the script, and
# get_header() falls back from the platform folder to the flat one.
PLATFORMS = ("pve", "incus")

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
                # A pve/ or incus/ segment anywhere in the path marks the
                # script as platform-specific, whatever its type. Everything
                # else is agnostic and lands flat under its type.
                parts = script.relative_to(root).parts[:-1]
                platform = next((p for p in parts if p in PLATFORMS), None)
                target = f"{app_type}/{platform}" if platform else app_type
                key = (target, slug(app))
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
