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
  build-ui.func        whiptail wizard, validators, advanced settings
  core.func            colors, spinners, messaging, silent()
  tools.func           helper library used by install scripts
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

tools/      developer helpers (run.sh)
images/     logos used in container MOTD and VM output
```

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
3. **Defaults** — `community-scripts/core@main` and `community-scripts/ProxmoxVE@main`

### Environment variables

| Variable | Root | Purpose |
| -------- | ---- | ------- |
| `COMMUNITY_SCRIPTS_CORE_DIR` | engine | Local core checkout |
| `COMMUNITY_SCRIPTS_CORE_URL` | engine | Raw base for the engine |
| `COMMUNITY_SCRIPTS_ROOT` | scripts | Local script-repo checkout |
| `COMMUNITY_SCRIPTS_URL` | scripts | Raw base for the scripts |
| `COMMUNITY_SCRIPTS_STATE_DIR` | — | Defaults, diagnostics and build logs |
| `LXC_PLATFORM` | — | Force `pve`, `incus` or `incus-container` (debugging) |

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
| Proxmox VE host | `pveversion` present | `pve/pve-backend.func` |
| Incus host | `incus` CLI and a reachable daemon | `incus/incus-build.func` |
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
- Never hardcode a raw URL. Use `_cs_source_func "misc/<name>.func"` so the
  resolver keeps forks working.
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
