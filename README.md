<div align="center">
  <img src="https://raw.githubusercontent.com/community-scripts/core/main/images/logo-81x112.png" height="112px" alt="Community Scripts Logo" />

  <h1>Community Scripts — Core</h1>
  <p><strong>The shared shell engine behind the community-scripts projects</strong><br/>
  Container and VM builds for Proxmox VE and Incus, from one codebase</p>

  <p>
    <a href="https://community-scripts.org"><img src="https://img.shields.io/badge/Website-community--scripts.org-4c9b3f?style=flat-square" /></a>
    <a href="https://discord.gg/3AnUqsXnmK"><img src="https://img.shields.io/badge/Discord-Join_us-7289da?style=flat-square&logo=discord&logoColor=white" /></a>
    <a href="https://github.com/community-scripts/core/stargazers"><img src="https://img.shields.io/github/stars/community-scripts/core?style=flat-square&label=Stars&color=f5a623" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" /></a>
  </p>
</div>

---

## What is this?

**The engine, not the scripts.**

This repository holds the shared Bash libraries that every community script
runs on: argument parsing, the whiptail wizard, container and VM creation, the
in-container installer, error handling, telemetry and the helper library.

You do not run anything from here directly. Application scripts live in the
script repositories and source this engine at start-up.

The engine detects the host at runtime and loads the matching backend, so a
single `ct/` script works on both Proxmox VE and Incus — there is no separate
Incus script tree.

---

## Status

**The split is in progress.** Extracting the engine is done, but the script
repositories have not been moved over yet:

| Repository | Scripts bootstrapping from core |
| ---------- | ------------------------------- |
| ProxmoxVED | 1 of 95 (`ct/debian.sh`, the pilot) |
| ProxmoxVE | 0 of 577 — untouched, still ships and loads its own `misc/` |

Everything else still sources its own in-repo `misc/build.func`. So the fork and
branch workflow described below works **today only for the converted scripts**;
pointing `COMMUNITY_SCRIPTS_CORE_URL` at a fork has no effect on a script that
never loads core in the first place.

ProxmoxVE stays untouched until the mechanism is proven in ProxmoxVED. See
[Divergence from ProxmoxVE](#divergence-from-proxmoxve) for what has to be
ported before it can move.

---

## Repository map

| Repository | Contains |
| ---------- | -------- |
| **core** (this repo) | The engine — `shared/`, `pve/`, `incus/` |
| [ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) | Application scripts — `ct/`, `install/`, `vm/`, `json/`, and `tools/pve/` |
| [ProxmoxVED](https://github.com/community-scripts/ProxmoxVED) | Where new scripts are tested before they move to ProxmoxVE |
| [Incus](https://github.com/community-scripts/Incus) | Incus host tooling and documentation |

---

## Layout

```
shared/     platform-agnostic engine
  build.func           entry point, origin resolution, platform dispatch
  build-ui.func        whiptail wizard entry point (loader)
  build-ui/validate.func   container id, hostname, network, IP range validators
  build-ui/defaults.func   storage selection, .vars files, app defaults
  build-ui/advanced.func   the advanced settings wizard
  build-ui/menu.func       settings and diagnostics menus, install_script, start
  core.func            colors, spinners, messaging, silent()
  tools.func           helper library used by install scripts (loader)
  tools/system.func      packages, repositories, OS probes, services
  tools/forge.func       GitHub, GitLab and Codeberg releases
  tools/runtime.func     language runtimes and application installers
  tools/db.func          databases and search engines
  tools/hwaccel.func     GPU detection and hardware acceleration
  install.func         in-container bootstrap (multi-distro)
  alpine-install.func  in-container bootstrap for Alpine
  alpine-tools.func    helper library for Alpine
  api.func             telemetry reporting
  error_handler.func   traps, diagnostics, exit codes
  preflight.func       host readiness checks
  cloud-init.func      cloud-init generation for VMs
  lxc-platform.func    host detection (Proxmox VE / Incus / in-container)
  source-origin.func   git remote → raw content base

pve/        Proxmox VE backend
  backend.func         container creation via pct
  vm-core.func         VM creation via qm
  vm-app.func          VM application provisioning

incus/      Incus backend
  build.func           entry hooks over the shared wizard
  backend.func         container creation via the incus CLI
  core.func            messaging and compatibility layer
  tools.func           Incus-side helper wrappers
  vm-core.func         VM creation on Incus

headers/    figlet banners, generated from the script repos
  <type>/              ct, addon, vm, tools — the banner for both platforms
  <type>/pve/          only when that script exists on Proxmox VE alone
  <type>/incus/        only when that script exists on Incus alone

tools/      developer helpers (run.sh)
images/     logos used in container MOTD and VM output
```

### Why headers live here

A header is a figlet banner derived from a script's `APP=` line — a generated
artifact, never hand-written. The same banner renders on both platforms, so
keeping a copy in every script repo was pure duplication.
`.github/workflows/generate-headers.yml` walks ProxmoxVE, ProxmoxVED and Incus
every six hours (or immediately on a `scripts-changed` dispatch) and regenerates
the tree.

They are keyed by `APP_TYPE`, not by the folder a script lives in — scripts
under `tools/addon/` declare `APP_TYPE="addon"`.

The platform subfolder is **optional and applies to every type**. Most scripts
run on both hosts and their banner sits flat under the type. A script that
exists on one platform only — host tools today, Incus VMs or a host-touching
add-on tomorrow — gets a `pve/` or `incus/` subfolder, and the generator decides
that purely from a `pve/` or `incus/` segment in the script's path. So a repo
opts in by where it puts the script, with no engine change and no new variable.

`get_header()` tries the platform folder first and falls back to the flat one,
which means an Incus-only VM script will be picked up automatically the day it
lands in `vm/incus/`. A newly merged script has no banner until the generator
has run; `header_info()` prints nothing in that case rather than failing.

---

## How loading works

The engine and the scripts live in different repositories, so both are resolved
independently. A CT script bootstraps the engine, and everything after that
goes through the resolver in `shared/build.func`:

| Path prefix | Resolves against | Example |
| ----------- | ---------------- | ------- |
| `shared/`, `pve/`, `incus/` | **engine root** | `pve/backend.func` → `core/pve/backend.func` |
| everything else | **scripts root** | `install/debian-install.sh` → `ProxmoxVE/install/debian-install.sh` |

Paths are folder-qualified, so the prefix alone decides the root and there is no
name-to-folder map to keep in sync. It is also what lets the backend files drop
their platform prefix: `incus/build.func` and `shared/build.func` can coexist
because nothing resolves by basename.

### Resolution order

1. **Local checkout** — used when found, so development needs no network at all
2. **Git origin** — a checkout's own `remote` and branch become its raw base, so a fork or branch is picked up automatically
3. **Defaults** — `community-scripts/core@main` for the engine, `community-scripts/ProxmoxVED@main` for the scripts

### Environment variables

| Variable | Root | Purpose |
| -------- | ---- | ------- |
| `COMMUNITY_SCRIPTS_CORE_DIR` | engine | Local core checkout |
| `COMMUNITY_SCRIPTS_CORE_URL` | engine | Raw base for the engine |
| `COMMUNITY_SCRIPTS_ROOT` | scripts | Local script-repo checkout |
| `COMMUNITY_SCRIPTS_URL` | scripts | Raw base for the scripts |
| `COMMUNITY_SCRIPTS_DIR` | engine | Back-compat alias for `…_CORE_DIR` |
| `COMMUNITY_SCRIPTS_STATE_DIR` | — | Defaults, diagnostics and build logs |
| `LXC_PLATFORM` | — | Force `pve`, `incus`, `incus-container` or `container` (debugging) |

---

## Testing a fork or branch

Because the two roots are independent, either side can be swapped without
touching the other. This is what makes fork-based development work.

**Local checkouts** — clone core next to the script repo and just run a script.
No configuration, no network:

```bash
git clone https://github.com/YOU/core
git clone https://github.com/YOU/ProxmoxVE
cd ProxmoxVE && bash ct/debian.sh
```

Each checkout's git remote and branch become its raw base automatically, so a
container built this way pulls the rest from your fork, not from upstream.

**Remote fork, engine only** — production scripts against your core branch:

```bash
export COMMUNITY_SCRIPTS_CORE_URL=https://raw.githubusercontent.com/YOU/core/my-branch
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/debian.sh)"
```

**Remote fork, both sides** — see `tools/run.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/community-scripts/core/main/tools/run.sh |
  bash -s -- https://raw.githubusercontent.com/YOU/ProxmoxVE/my-branch ct/debian.sh \
             https://raw.githubusercontent.com/YOU/core/my-branch
```

---

## Platform detection

| Environment | Detected by | Backend |
| ----------- | ----------- | ------- |
| Proxmox VE host | `pveversion` present | `pve/backend.func` |
| Incus host | `incus` CLI and a reachable daemon | `incus/build.func` |
| Inside an Incus container | `/dev/incus/sock` or the Community Scripts MOTD | update mode |

Override with `LXC_PLATFORM` when debugging.

Host tools are the one thing that cannot be shared: `tools/pve/` scripts call
`pve*` binaries, and their Incus counterparts live in the Incus repository.

---

## Contributing

Engine changes affect every script in the collection at once, so they get more
scrutiny than an application script.

| I want to… | Go here |
| ---------- | ------- |
| Change the engine | Open a PR here, and say which platforms you tested on |
| Add or fix an application script | [ProxmoxVED](https://github.com/community-scripts/ProxmoxVED) for new ones, [ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) for fixes |
| Add Incus host tooling | [Incus](https://github.com/community-scripts/Incus) |
| Report a bug | [Issues](https://github.com/community-scripts/core/issues) — include your host platform and whether it reproduces on the other one |
| Ask a question | [Discord](https://discord.gg/3AnUqsXnmK) |

Before opening a PR:

- Test on **both** backends when you touch `shared/`. A change that only works
  on Proxmox VE belongs in `pve/`.
- Never hardcode a raw URL. Use `_cs_source_func "shared/<name>.func"` (or
  `pve/…`, `incus/…`) so both roots keep resolving and forks keep working.
- `shared/tools.func` and `shared/build-ui.func` are loaders. Source those, not
  the parts under `shared/tools/` or `shared/build-ui/`. If you add or rename a
  function, regenerate the matching `API.txt` in the same PR — CI compares
  against it.
- New files go in the folder that matches their root. Nothing resolves by
  basename, so `incus/tools.func` and `shared/tools.func` are both fine.
- `shellcheck` and `shfmt` the files you touched.

---

## Divergence from ProxmoxVE

The engine here comes from the ProxmoxVED lineage. Production **ProxmoxVE**
still ships its own `misc/*.func` and has drifted in a few places. Nothing
below is broken today — ProxmoxVE loads its own copy — but each item is a
regression waiting to happen when ProxmoxVE is folded onto this repo.

**Missing here, must be ported first:**
`configure_http_proxy` and the `var_http_proxy` / `var_http_no_proxy` chain ·
`var_inherit_host_ca` · `var_github_token` · `nginx_enable_site()` ·
`get_php_fpm_socket()` (19 ProxmoxVE install scripts call it) ·
the `_bootstrap_die` / `_bootstrap_source` download hardening.

**Behaviour differences to reconcile:**
`silent()` ends with `exit` here but `return` in ProxmoxVE, so a caller cannot
handle its own failure · `apt_update_safe` is *called* by `ensure_whiptail` but
never defined here, which silently skips an `apt-get update`.

**Already ahead here — do not regress when merging:**
the multi-distro `install.func` · the whole Incus backend and platform split ·
`setup_cloud_init_network_no_rename` · telemetry `platform` reporting.

---

## License

MIT — free to use, modify and redistribute. See [LICENSE](LICENSE).

---

<div align="center">
  <sub>Built on the foundation of <a href="https://github.com/tteck">tteck</a>'s original work · In memory of tteck</sub><br/>
  <sub><i>Proxmox® is a registered trademark of <a href="https://www.proxmox.com/en/about/company">Proxmox Server Solutions GmbH</a>. Incus is a project of <a href="https://linuxcontainers.org/">LinuxContainers</a>.</i></sub>
</div>
