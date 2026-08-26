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

## Where the Incus backend has to differ

The two backends aim to behave the same. Most of the differences below are not
choices — they are things Incus does that `pct` does not.

**Its output is translated.** `incus storage info` on a German host reports
"Gesamter Speicherplatz", so every parse in the backend runs under `LC_ALL=C`.
Free space is read in bytes where the pool reports it and falls back to `df` on
the pool source; unparseable stays `unknown` rather than becoming a wrong number.
The figure is *pool* free space, not host disk — a default loop-backed pool is
often around 10 GiB, which is why the backend prints how to grow it.

**Not every operator is root.** An Incus host is routinely driven by an
unprivileged user. That is why `community_scripts_dir()` exists at all, and why
the header cache, logs and defaults all go through it. It also means
`kernel.keys.maxkeys` cannot be written from an unprivileged user namespace, so
that sysctl is set only for privileged containers, and only when the host value
is actually below the target.

**Optional settings must not brick the container.** A rejected `linux.sysctl.*`
key stops the instance from starting, so they are applied softly and rolled back
on failure — and the rollback confirms the container really is running via
`incus list -c s`, rather than trusting the exit status of a start.

**No pty.** The install runs through `incus exec` *without* `-t`. Allocating one
looks harmless and is not: apt's dpkg progress does a `tcsetattr` on stdin, gets
`EIO`, and the shell dies mid-install while the run still reports success. The
consequence is that the spinner has no terminal to draw on, so `CS_ANIMATION_OK`
tells [`core/core.func`](../core/core.func) it may animate anyway, and the real
exit status comes from `PIPESTATUS` plus a sentinel file rather than from the
pipeline.

**Containers can start without a timezone.** Some images ship no
`/etc/timezone`, which breaks packages that read it, so
[`lxc/install.func`](../lxc/install.func) backfills it from the requested `tz`,
from `/etc/localtime`, or from `Etc/UTC`.

**The version line is not "PVE Version".** `_cs_host_version_line()` in
[`core/core.func`](../core/core.func) renders "Incus Version 6.x" on an Incus
host and "PVE Version …" on Proxmox VE, from the same `PVEVERSION` value.
