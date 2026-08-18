# core — documentation

This repository is the **engine**, not the scripts. It holds the Bash libraries
that application scripts source at start-up: the wizard, container and VM
creation, the in-container installer, error handling, telemetry and the helper
library used by install scripts.

Nothing here is run directly. A script in
[ProxmoxVE](https://github.com/community-scripts/ProxmoxVE),
[ProxmoxVED](https://github.com/community-scripts/ProxmoxVED) or
[Incus](https://github.com/community-scripts/Incus) sources
[`core/build.func`](../core/build.func) as its first act, and everything else
follows from there.

## Where things are

| Folder | What it is | Page |
| ------ | ---------- | ---- |
| [`core/`](../core/) | Entry point, runtime, error handling, dev mode | [core.md](core.md) |
| [`ui/`](../ui/) | The whiptail wizard | [ui.md](ui.md) |
| [`lib/`](../lib/) | Helper library that install scripts call | [lib.md](lib.md) |
| [`lxc/`](../lxc/) | What runs inside the container | [lxc.md](lxc.md) |
| [`host/`](../host/) | Checks and helpers that run on the host | [host.md](host.md) |
| [`api/`](../api/) | Telemetry reporting | [api.md](api.md) |
| [`vm/`](../vm/) | Cloud-init generation for VMs | [vm.md](vm.md) |
| [`pve/`](../pve/), [`incus/`](../incus/) | The two platform backends | [backends.md](backends.md) |
| [`headers/`](../headers/) | Generated figlet banners | [headers.md](headers.md) |
| [`tools/`](../tools/) | `run.sh`, the fork and branch runner | [loading.md](loading.md#running-against-a-fork) |
| [`images/`](../images/) | Logos used in container MOTD and VM output | — |

## How it fits together

[loading.md](loading.md) is the one to read first if you are changing anything
structural. It covers how the engine and the script repositories resolve
independently, what the two roots are, how a local checkout or a fork takes
over, and how the engine is prefetched in a single round trip.

[dev-mode.md](dev-mode.md) covers the opt-in debugging flags.

[testing-builds.md](testing-builds.md) covers `var_testurl` — how a script under
test asks for feedback, and what it changes.

[contributing.md](contributing.md) covers the rules that CI enforces — where a
new file goes, which files are loaders, and when an `API.txt` has to be
regenerated.

[proxmoxve-migration.md](proxmoxve-migration.md) tracks what stands between this
engine and ProxmoxVE, which has not moved over yet.

## Every file

| File | Purpose |
| ---- | ------- |
| [`core/build.func`](../core/build.func) | Entry point: resolves both roots, prefetches the engine, dispatches to a platform backend |
| [`core/core.func`](../core/core.func) | Colours, icons, `msg_*`, spinner, `silent()`, logging, prompts |
| [`core/error_handler.func`](../core/error_handler.func) | `catch_errors`, the ERR trap, signal handlers, container failure artifacts |
| [`core/dev-mode.func`](../core/dev-mode.func) | Opt-in developer flags, timing and tracing |
| [`ui/build-ui.func`](../ui/build-ui.func) | Wizard entry point; sources the four parts below |
| [`ui/validate.func`](../ui/validate.func) | Container ID, hostname, network and IP-range validators |
| [`ui/defaults.func`](../ui/defaults.func) | Storage selection, `.vars` files, app defaults |
| [`ui/advanced.func`](../ui/advanced.func) | The advanced settings wizard |
| [`ui/menu.func`](../ui/menu.func) | `start`, `install_script`, settings and diagnostics menus |
| [`lib/tools.func`](../lib/tools.func) | Helper library entry point; sources the five parts below |
| [`lib/system.func`](../lib/system.func) | Packages, repositories, OS probes, services, temp files |
| [`lib/forge.func`](../lib/forge.func) | Releases, tags and branches from GitHub, GitLab and Codeberg |
| [`lib/runtime.func`](../lib/runtime.func) | Language runtimes and application installers |
| [`lib/db.func`](../lib/db.func) | Databases and search engines |
| [`lib/hwaccel.func`](../lib/hwaccel.func) | GPU detection and hardware acceleration |
| [`lib/alpine.func`](../lib/alpine.func) | The Alpine helper library, loaded instead of the above |
| [`lxc/install.func`](../lxc/install.func) | In-container bootstrap, every distro including Alpine |
| [`lxc/platform.func`](../lxc/platform.func) | Proxmox VE / Incus / in-container detection |
| [`host/preflight.func`](../host/preflight.func) | Optional host readiness checks, off by default |
| [`host/validate.func`](../host/validate.func) | MAC, VLAN and MTU checks shared by both platforms |
| [`host/source-origin.func`](../host/source-origin.func) | Git remote to raw content base |
| [`api/api.func`](../api/api.func) | Telemetry entry point; sources the four parts below |
| [`api/exitcodes.func`](../api/exitcodes.func) | The exit code table |
| [`api/errorlog.func`](../api/errorlog.func) | Error capture and log selection |
| [`api/sysinfo.func`](../api/sysinfo.func) | Host and container facts, origin detection |
| [`api/telemetry.func`](../api/telemetry.func) | Payload assembly and delivery |
| [`vm/cloud-init.func`](../vm/cloud-init.func) | Cloud-init configuration for VMs |
| [`pve/backend.func`](../pve/backend.func) | Container creation via `pct` |
| [`pve/vm-core.func`](../pve/vm-core.func) | VM creation via `qm` |
| [`pve/vm-app.func`](../pve/vm-app.func) | Running LXC applications inside a VM |
| [`incus/build.func`](../incus/build.func) | Incus entry hooks over the shared wizard |
| [`incus/backend.func`](../incus/backend.func) | Container creation via the `incus` CLI |
| [`incus/core.func`](../incus/core.func) | Incus messaging and compatibility layer |
| [`incus/tools.func`](../incus/tools.func) | Incus-side helper wrappers |
| [`incus/vm-core.func`](../incus/vm-core.func) | VM creation on Incus |
