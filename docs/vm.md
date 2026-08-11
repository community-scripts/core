# `vm/` — cloud-init

Back to the [index](README.md).

## [`cloud-init.func`](../vm/cloud-init.func)

Cloud-init configuration for VMs: SSH key discovery and selection
(`configure_cloudinit_ssh_keys`), network configuration and validation, and
`setup_cloud_init` / `configure_cloud_init_interactive`.

Loaded by [`pve/vm-core.func`](../pve/vm-core.func) only. The Incus VM path
([`incus/vm-core.func`](../incus/vm-core.func)) does not use it — Incus drives
its own instance configuration through the `incus` CLI.

One thing to know before editing it: this is the only file in the repository
that declares functions as `function name() {` rather than `name() {`. Anything
that greps for function definitions across the engine will miss them unless it
accounts for that.
