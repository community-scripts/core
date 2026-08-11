# `pve/` and `incus/` — the platform backends

Back to the [index](README.md).

A single `ct/` script works on both Proxmox VE and Incus. There is no separate
Incus script tree: [`core/build.func`](../core/build.func) detects the host
through [`lxc/platform.func`](../lxc/platform.func) and loads the matching
backend, which overrides the storage, network and create hooks the shared
wizard calls.

## `pve/` — Proxmox VE

| File | Purpose |
| ---- | ------- |
| [`backend.func`](../pve/backend.func) | `build_container`, `create_lxc_container`, storage helpers, container description, traps. Container creation via `pct`. |
| [`vm-core.func`](../pve/vm-core.func) | VM creation via `qm`, including disk import and template handling |
| [`vm-app.func`](../pve/vm-app.func) | Deploys an application that normally goes into an LXC container into a full VM instead |

## `incus/` — Incus

| File | Purpose |
| ---- | ------- |
| [`build.func`](../incus/build.func) | Entry hooks over the shared wizard. Loaded automatically on Incus hosts and Incus containers. |
| [`backend.func`](../incus/backend.func) | Container creation via the `incus` CLI, mirroring the Proxmox flow |
| [`core.func`](../incus/core.func) | Incus messaging, formatting and compatibility layer |
| [`tools.func`](../incus/tools.func) | Incus-side wrappers giving parity with the host tools |
| [`vm-core.func`](../incus/vm-core.func) | VM creation on an Incus host |

`incus/build.func`, `incus/core.func` and `incus/tools.func` share a basename
with files elsewhere in the repository. That is fine: nothing resolves by
basename, only by folder-qualified path.
