# `host/` — what runs on the host

Back to the [index](README.md).

## [`preflight.func`](../host/preflight.func)

Optional host readiness checks. **Off by default** — they only run when
`ENABLE_PREFLIGHT=1` is set. They were extracted from the build UI and are not
part of a normal install.

## [`validate.func`](../host/validate.func)

`validate_mac_address`, `validate_vlan_tag`, `validate_mtu`.

These are here rather than in [`ui/`](../ui/) because whether an MTU is in range
or a MAC looks like a MAC does not depend on whether the host runs Proxmox VE or
Incus. Only what happens with the value afterwards does. `pve/vm-core.func` and
`incus/vm-core.func` both load this file directly.

## [`source-origin.func`](../host/source-origin.func)

`cs_git_remote_to_raw_base` and `cs_detect_origin_from_git`: turn a checkout's
own git remote and branch into a raw content base, so working in a fork or on a
branch picks itself up without any configuration. Loaded by
[`core/build.func`](../core/build.func) when running from a local checkout.

CT scripts do not source this directly.
