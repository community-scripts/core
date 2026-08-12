# Folding ProxmoxVE onto core

Back to the [index](README.md).

ProxmoxVED and Incus bootstrap from this repository. ProxmoxVE does not: all 583
of its `ct/` scripts still load its own in-repo `misc/*.func`. This page tracks
what stands between the two.

The engine here comes from the ProxmoxVED lineage, so the two copies drifted.
Nothing is broken today — ProxmoxVE loads its own copy — but each gap is a
regression waiting to happen the day it is folded onto this repo.

## Previously blocking, now present

These were listed as missing from core and had to be ported before a merge.
Checked against the current tree, all of them exist here:

| Item | Where it is now |
| ---- | --------------- |
| `configure_http_proxy`, `var_http_proxy`, `var_http_no_proxy` | [`core/core.func`](../core/core.func) |
| `var_inherit_host_ca` | present |
| `var_github_token` | present |
| `nginx_enable_site` | [`lib/runtime.func`](../lib/runtime.func) |
| `get_php_fpm_socket` | [`lib/runtime.func`](../lib/runtime.func) |
| `_bootstrap_die` / `_bootstrap_source` download hardening | [`lxc/alpine-install.func`](../lxc/alpine-install.func) |
| `apt_update_safe` — was called by `ensure_whiptail` but undefined | [`core/core.func`](../core/core.func) |
| `silent()` ending in `exit` rather than `return` | now ends in `return "$rc"` |
| The container notes still used the Ko-fi badge and Gitea links | ported to the script page and sponsoring badges |

Re-verify before the merge rather than trusting this table: it is a snapshot,
and ProxmoxVE keeps moving too.

## Better in ProxmoxVE — worth porting

From a function-level comparison of the whole of `ProxmoxVE/misc/` against this
engine: 371 functions there, 593 here, 358 shared, of which 250 are byte-identical
once comments and whitespace are ignored. Only `_send_abort_telemetry` exists
there and not here, and that one was deleted deliberately.

Of the 108 that differ, most are explained by refactors on this side — the forge
consolidation left one-line wrappers, `error_handler` was split into `_eh_*`
steps, `get_lxc_ip` had its body moved into `_get_current_ip`. What is left:

| Function | What ProxmoxVE does better | Severity |
| -------- | -------------------------- | -------- |
| `validate_container_id` | Checks the **whole cluster** — `pvesh get /cluster/resources` plus a walk of `/etc/pve/nodes/*/`. This engine only looks at `/etc/pve/qemu-server/` and `/etc/pve/lxc/`, which resolve to the local node, so an ID already in use on another node is not detected. | **Bug on clusters** |
| `get_valid_container_id` | Bounded retry (`max_attempts=1000`) and a numeric guard on the `pvesh get /cluster/nextid` result. Here the loop is unbounded and an empty `pvesh` result falls through to arithmetic on an empty string. Exit code 109 is documented for this and never used. | **Bug** |
| `diagnostics_menu` | Shows current telemetry state and links to `telemetry.community-scripts.org` in the dialog. | Cosmetic |
| `check_or_create_swap` | Reports which step failed (allocate, chmod, mkswap, swapon) with distinct exit codes rather than one generic failure. | Cosmetic |
| `update_os` (Alpine) | Shuffles the mirror list instead of always trying them in the same order. | Marginal |

## Ahead here — do not regress when merging

- The multi-distro [`lxc/install.func`](../lxc/install.func)
- The whole Incus backend and the platform split
- `setup_cloud_init_network_no_rename` in [`vm/cloud-init.func`](../vm/cloud-init.func)
- Telemetry `platform` reporting

## Why ProxmoxVE waits

The mechanism gets proven in ProxmoxVED first. Until ProxmoxVE moves, pointing
`COMMUNITY_SCRIPTS_CORE_URL` at a fork has no effect on a ProxmoxVE script,
because that script never loads core at all.
