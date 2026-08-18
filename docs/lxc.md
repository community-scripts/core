# `lxc/` — what runs inside the container

Back to the [index](README.md).

Once the host has created a container, it runs one of these inside it. The host
passes the file through the environment (`FUNCTIONS_FILE_PATH`), which
`lxc-attach` carries into the container.

## [`install.func`](../lxc/install.func)

The multi-distro bootstrap: Debian, Ubuntu, Devuan, Fedora, Rocky, Alma,
CentOS, openSUSE, Gentoo, openEuler.

A container has its own filesystem, so the host's prefetch cannot help it.
`_cs_ct_prefetch_engine` therefore fetches the container's own subset
concurrently on this side, listed in `_CS_CT_ENGINE_FILES`, and
`_cs_engine_read` reads from that copy or falls back to the network. Names are
folder-qualified paths, the same as on the host.

Which helper library gets loaded is decided here: `lib/alpine.func` for Alpine,
`lib/tools.func` otherwise.

Alpine used to get its own bootstrap, `alpine-install.func`. It was a second,
thinner copy of the same eight functions, so every fix had to be made twice and
`install.func`'s own apk and OpenRC branches never ran. Both backends now hand
`install.func` to every container and `detect_os` decides the rest.

## [`platform.func`](../lxc/platform.func)

`detect_lxc_platform` and the predicates around it (`is_incus_host`,
`is_incus_container`, `is_incus_lxc_backend`). This is what
[`core/build.func`](../core/build.func) uses to decide which backend to load:
a Proxmox VE host, an Incus host, or already inside a container.
