# `vm/` — cloud-init and shared VM helpers

Back to the [index](README.md).

## [`cloud-init.func`](../vm/cloud-init.func)

Cloud-init configuration for VMs: SSH key discovery and selection
(`configure_cloudinit_ssh_keys`), network configuration and validation, and
`setup_cloud_init` / `configure_cloud_init_interactive`.

The interactive half is split in two. `configure_cloud_init_interactive` runs
before the Default/Advanced fork — it asks whether to use cloud-init at all
(the answer picks the disk image) plus the username and password, and then
defaults the rest to DHCP, `CLOUDINIT_DNS_SERVERS` and no SSH keys.
`configure_cloud_init_advanced` and `configure_cloudinit_ssh_keys` ask for the
rest and are reached only through `vm_prompt_cloud_init_advanced`, on the
Advanced path.

Loaded by [`pve/vm-core.func`](../pve/vm-core.func) only. The Incus VM path
([`incus/vm-core.func`](../incus/vm-core.func)) does not use it — Incus drives
its own instance configuration through the `incus` CLI.

`load_cloud_init_functions` exists on the Incus side too, and always returns
non-zero after saying so once. That is deliberate: a Proxmox-shaped script
guards its `setup_cloud_init` call on that return value, so reporting the
helpers as unavailable is what keeps it on its fallback branch instead of
letting it call into a function that would need `qm`. `vm_provision` applies
the same `CLOUDINIT_*` variables through the `cloud-init.*` instance keys.

`get_vm_ip <vmid> [timeout] [mac]` reads addresses through the guest agent.
Pass the VM's MAC: only that NIC then counts, which is the only reliable answer
once the guest runs Docker, Podman or Kubernetes. Without a MAC, bridge and
tunnel interfaces those create are skipped; loopback and link-local addresses
never count. `wait_for_cloud_init` asks the guest agent
(`cloud-init status --wait`) first, which needs neither an address nor SSH
keys, and falls back to SSH only for guests without an agent.

One thing to know before editing it: this file declares its functions as
`function name() {` rather than `name() {` — the only one that does, apart from
`get_lxc_ip` in [`core/core.func`](../core/core.func). Anything that greps for
function definitions across the engine will miss them unless it accounts for
that.

## [`common.func`](../vm/common.func)

Helpers a VM script needs whatever the hypervisor. Both
[`pve/vm-core.func`](../pve/vm-core.func) and
[`incus/vm-core.func`](../incus/vm-core.func) load it, so a script finds the
same functions on either host. Nothing in it calls `qm` or `incus`.

| Function | Contract |
| --- | --- |
| `vm_require_tools <cmd>...` | Installs the packages for missing commands (`jq`, `xz`, `virt-customize`, `unzip`, `zstd`, `7z`, …) before anything is created; returns non-zero, with the reason, when it cannot. |
| `vm_release_asset <github\|gitlab\|codeberg> <owner/repo> <asset regex> [tag]` | Resolves a release through [`lib/forge.func`](../lib/forge.func) — tokens, rate limits and the API-less GitHub fallback included. Sets `VM_RELEASE_TAG`, `VM_RELEASE_VERSION`, `VM_RELEASE_ASSET`, `VM_RELEASE_URL` and, from GitHub's asset digest, `VM_RELEASE_SHA256`. |
| `vm_latest_from_index <url> <pcre> [--sort-by <pcre>] [--probe <url with {}>]...` | Newest match on an HTML download index (`grep -oP`, so `\K` works). `--sort-by` orders by part of the match; each `--probe` template is tried newest first and the first answering URL wins. Sets `VM_INDEX_LATEST` and `VM_INDEX_URL`. Never falls back to a hardcoded release. |
| `vm_firstboot_unit <image> <name> <script> [--description …] [--after <unit>]... [--requires-path <path>] [--cloud-init yes\|no]` | Stages `<script>` as `/usr/local/sbin/<name>` plus a run-once `<name>.service`. The marker `/var/lib/community-scripts/<name>.done` (`VM_FIRSTBOOT_MARKER`) is written only after success, so a failure is retried on the next boot. With Cloud-Init the unit is wanted by `cloud-init.target` and ordered after `cloud-final.service`; wanting `multi-user.target` there would create an ordering cycle. |
| `vm_wait_http <url> [timeout] [--insecure]` | Succeeds on any 2xx/3xx, or 401/403 from a login page. |
| `vm_print_summary ["Label=value"]...`, `vm_next_steps <step>...`, `vm_finish [message]` | The standard closing block: VM ID, hostname, resources, state and `VM_IP`, extra rows, numbered next steps, then the `done` telemetry and the completion message. |

Checksums: `vm_fetch_image` verifies the vendor checksum for Debian, Ubuntu,
TrueNAS, OpenWrt (`sha256sums`), FreeBSD VM images (`CHECKSUM.SHA256`) and
TurnKey (`.hash`) by itself. Elsewhere pass `--sha256` (for example
`VM_RELEASE_SHA256`) or `--checksum-url <sums file>`; GNU, BSD and bare-hash
layouts are understood and the algorithm follows from the hash length.

### Proxmox-only counterparts

[`pve/vm-core.func`](../pve/vm-core.func) adds the steps that drive `qm`:

| Function | Contract |
| --- | --- |
| `vm_import_disk <vmid> <image> <storage> [format]` | `qm disk import` (or `qm importdisk` on older hosts) with `DISK_IMPORT_FORMAT`; sets `VM_IMPORTED_DISK` to the volume Proxmox reported or the `unusedN` entry the import added. Never guesses a name. |
| `vm_start_vm [label]` | Starts the VM when `START_VM=yes`. |
| `vm_wait_guest_agent <vmid> [timeout]` | Waits until the guest agent answers. |
| `vm_guest_exec <vmid> <timeout> [--] <cmd>...` | Runs a command through the guest agent; prints its stdout and returns its exit code (124: still running). |
| `vm_wait_for_ip [timeout]` | Sets `VM_IP` from the NIC matching `MAC`; warns and returns non-zero when there is none yet. |

On Incus these fail with exit 119 and say why: `incus_vm_create` imports,
starts and waits for the agent itself.

Run the host-independent regression tests with `bash tests/vm-helpers.sh`.
