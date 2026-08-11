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

`get_header()` tries the platform folder first and falls back to the flat one,
which means a platform-only script is picked up automatically the day it lands.
A newly merged script has no banner until the generator has run; `header_info()`
prints nothing in that case rather than failing.
