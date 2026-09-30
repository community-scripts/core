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

## VM scripts on the two backends

`ct/` scripts are shared; `vm/` scripts are not, and the reason is worth
knowing before trying to unify them.

[`incus/vm-core.func`](../incus/vm-core.func) now carries every function name
[`pve/vm-core.func`](../pve/vm-core.func) exports to a VM script, with the same
argument order, so the wizard, the image download, the image preparation and
the disk sizing all behave the same on either host. Three groups of them differ
in what they can actually do:

- **The same code.** Downloading and verifying a vendor image, and preparing it
  with libguestfs, is curl and `virt-customize` on both — `vm_fetch_image`,
  `vm_image_cache_path`, `vm_expand_image` and `vm_prepare_cloud_image` are the
  same implementation, not a translation. The cache goes somewhere writable via
  `community_scripts_dir` rather than to `/var/lib/vz`, because an Incus
  operator is frequently not root.
- **A real Incus equivalent.** `vm_resize_disk` becomes
  `incus config device set <vm> root size=…`, `set_description` becomes
  `incus config set <vm> description=…`, `vm_select_storage` reads
  `incus storage list` instead of `pvesm status`, and `vm_prompt_bios` maps
  onto `security.csm`, which is the option Incus documents for
  UEFI-incompatible guests.
- **Nothing to map onto.** Incus has no numeric instance IDs, no QEMU machine
  type, no CPU model, no display adapter, no NIC model and no memory
  ballooning — none of them are instance options. Those functions exist, leave
  the variables they own defined so an interpolating script does not die on an
  unset variable, and say once through `msg_warn` that they did nothing. They
  do not pretend to have succeeded.

The one thing that is genuinely not portable is the creation itself. Every
script in `ProxmoxVE`/`ProxmoxVED` `vm/` runs `qm create`, `pvesm alloc`,
`qm importdisk` and `qm set` inline, and there is no `qm` on an Incus host.
`incus_vm_create` is the Incus counterpart for that block; it takes a remote
alias such as `images:debian/13` or, since a Proxmox VM script always downloads
one, a path to a local disk image. A local path is turned into an Incus image
first: the file is converted to qcow2 if it is not already (Incus classifies a
split image as a virtual machine by the qcow2 magic on the second file, so a
raw `.img` would otherwise be imported as a container root filesystem), a
metadata tarball is generated, and the two are handed to `incus image import`.

`qm sendkey` has no counterpart at all, so the scripts that drive an installer
through the console — OPNsense, OpenWrt — cannot be ported at any level.
