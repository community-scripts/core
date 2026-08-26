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
a Proxmox VE host, an Incus host, or already inside a container. It answers
`pve`, `incus`, `incus-container` or `container`; [loading.md](loading.md#platform-detection)
covers the order the tests run in and why.

Two supporting pieces live here as well:

- `_lxc_incus_bin` and `ensure_incus_on_path` — the `incus` client is not always
  on `PATH`, and detection finding it is not enough, because every later `incus`
  call in the engine has to resolve too.
- `community_scripts_dir` — the writable state directory for defaults,
  diagnostics, logs and the header cache. `/usr/local/community-scripts` for
  root, or wherever that path is writable; `~/.config/community-scripts`
  otherwise; `COMMUNITY_SCRIPTS_STATE_DIR` overrides both. It sits here rather
  than in `core/` because the non-root case is an Incus one — a Proxmox VE host
  is always root, an Incus host frequently is not.
