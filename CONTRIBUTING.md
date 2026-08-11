# Contributing

This repository is the engine behind the community-scripts projects. A change
here affects every script in the collection at once.

**The full guide is in [docs/contributing.md](docs/contributing.md)** — where a
change belongs, what CI enforces, and how to test one.

Short version:

- Application scripts do not live here. New ones go to
  [ProxmoxVED](https://github.com/community-scripts/ProxmoxVED), fixes to
  [ProxmoxVE](https://github.com/community-scripts/ProxmoxVE), Incus host
  tooling to [Incus](https://github.com/community-scripts/Incus).
- Source the loaders (`lib/tools.func`, `ui/build-ui.func`, `api/api.func`), not
  the parts beside them, and regenerate the matching `API.txt` when you change a
  function.
- List new engine files in `_CS_ENGINE_FILES` in `core/build.func`.
- Test on both Proxmox VE and Incus when the change is not backend-specific.

Start with [docs/README.md](docs/README.md) if you have not worked in this
repository before, and [docs/loading.md](docs/loading.md) before changing
anything structural.
