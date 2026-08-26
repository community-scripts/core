# `headers/` — generated banners

Back to the [index](README.md).

A header is a figlet banner derived from a script's `APP=` line — a generated
artifact, never hand-written. The same banner renders on both platforms, so
keeping a copy in every script repository was pure duplication.

`.github/workflows/generate-headers.yml` walks ProxmoxVE, ProxmoxVED and Incus
every six hours, or immediately on a `scripts-changed` dispatch, and regenerates
the tree.

## Layout

```
headers/<type>/            ct, addon, vm, tools — the banner for both platforms
headers/<type>/pve/        only when that script exists on Proxmox VE alone
headers/<type>/incus/      only when that script exists on Incus alone
```

They are keyed by `APP_TYPE`, not by the folder a script lives in — a script
under `tools/addon/` declares `APP_TYPE="addon"`.

The platform subfolder is optional and applies to every type. Most scripts run
on both hosts and their banner sits flat under the type. A script that exists on
one platform only gets a `pve/` or `incus/` subfolder, and the generator decides
that purely from a `pve/` or `incus/` segment in the script's path — so a
repository opts in by where it puts the script, with no engine change and no new
variable.

A platform-only script is picked up automatically the day it lands.

## The lookup

`get_header()` tries the flat path first, then the platform folder. The two sets
are disjoint — the platform folders hold only banners for scripts that have no
generic one — so the order cannot change which banner wins, only how often the
first request 404s. Generic first makes that zero for 673 of 673 ct runs.

Each candidate is tried against three sources in turn: a local core checkout
(`COMMUNITY_SCRIPTS_CORE_DIR`), so a fork renders its own banners; the on-disk
cache; and then the network, which populates the cache.

The cache lives under `community_scripts_dir()`, not a hardcoded
`/usr/local/community-scripts`. A non-root operator on an Incus host cannot
create that path, so the fetch had nowhere to write and every banner silently
vanished. When nothing is writable anywhere the banner is still drawn, just
uncached. An empty file is never left behind — it would satisfy the cache check
on every later run and suppress the banner permanently.

A newly merged script has no banner until the generator has run; `header_info()`
prints nothing in that case rather than failing.
