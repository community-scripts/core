# `ui/` — the whiptail wizard

Back to the [index](README.md).

Source [`build-ui.func`](../ui/build-ui.func). It sources the four parts below
in a fixed order; loading a part on its own will not work, because they depend
on each other and on [`core/core.func`](../core/core.func).

The wizard is shared by both platforms. A backend overrides the storage,
network and create hooks rather than shipping its own wizard.

## [`build-ui.func`](../ui/build-ui.func)

The loader, plus `variables` and `maxkeys_check`. It also decides whether the
optional preflight checks run — they are off unless `ENABLE_PREFLIGHT=1`.

## [`validate.func`](../ui/validate.func)

Input validation: `validate_container_id`, `validate_hostname`,
`validate_ip_address`, `validate_ipv6_address`, `validate_gateway_ip`,
`validate_gateway_in_subnet`, `validate_bridge`, `validate_sdn_vnet`,
`validate_timezone`, `validate_tags`. Also the IP-range helpers (`ip_to_int`,
`int_to_ip`, `resolve_ip_from_range`) used when a range is given instead of a
fixed address.

MAC, VLAN and MTU are not here — they do not depend on the platform, so they
live in [`host/validate.func`](../host/validate.func).

## [`defaults.func`](../ui/defaults.func)

Where settings come from and where they are kept: storage selection, the
global and per-app `.vars` files, app defaults, and the diff shown when a
saved default no longer matches what the script wants.

## [`advanced.func`](../ui/advanced.func)

`advanced_settings` — one function, the full interactive configuration path.

## [`menu.func`](../ui/menu.func)

The entry points and the menus:

- `start` — the first screen, and what a CT script reaches through `build.func`
- `install_script` — default / advanced / settings selection, then the build
- `settings_menu`, `diagnostics_menu`

`start` also backgrounds the `pvesh get /cluster/nextid` call so it overlaps
with the checks that follow, and falls back to a foreground call if that
returns nothing.
