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

This repository holds the shared Bash libraries that every community script runs
on: the whiptail wizard, container and VM creation, the in-container installer,
error handling, telemetry and the helper library.

You do not run anything from here directly. Application scripts live in the
script repositories and source this engine at start-up.

The engine detects the host at runtime and loads the matching backend, so a
single `ct/` script works on both Proxmox VE and Incus — there is no separate
Incus script tree.

---

## Documentation

**[docs/](docs/README.md)** — the index: what every folder and file is for.

| | |
| --- | --- |
| [How loading works](docs/loading.md) | The two roots, resolution order, the prefetch, running against a fork |
| [Contributing](docs/contributing.md) | Where a change belongs, what CI enforces, how to test |
| [Dev mode](docs/dev-mode.md) | The opt-in debugging flags |
| [Testing builds](docs/testing-builds.md) | `var_testurl` and how a script under test asks for feedback |
| [core/](docs/core.md) · [ui/](docs/ui.md) · [lib/](docs/lib.md) · [lxc/](docs/lxc.md) | |
| [host/](docs/host.md) · [api/](docs/api.md) · [vm/](docs/vm.md) · [backends](docs/backends.md) · [headers/](docs/headers.md) | |

---

## Repository map

| Repository | Contains |
| ---------- | -------- |
| **core** (this repo) | The engine |
| [ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) | Application scripts — `ct/`, `install/`, `vm/`, `json/`, `tools/pve/` |
| [ProxmoxVED](https://github.com/community-scripts/ProxmoxVED) | Where new scripts are tested before they move to ProxmoxVE |
| [Incus](https://github.com/community-scripts/Incus) | Incus scripts and host tooling |

---

## Status

The split is in progress. ProxmoxVED and Incus bootstrap from core; ProxmoxVE
does not yet and still ships and loads its own `misc/`.

| Repository | `ct/` scripts bootstrapping from core |
| ---------- | ------------------------------------ |
| ProxmoxVED | 104 of 104 |
| Incus | 577 of 577 |
| ProxmoxVE | 0 of 583 |

ProxmoxVE stays untouched until the mechanism is proven in ProxmoxVED. See
[docs/proxmoxve-migration.md](docs/proxmoxve-migration.md) for what stands
between the two.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Engine changes affect every script in the
collection at once, so they get more scrutiny than an application script — and
application scripts do not belong here.

## License

MIT — see [LICENSE](LICENSE).
