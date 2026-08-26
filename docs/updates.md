# `update` — what happens inside a container

Back to the [index](README.md).

Every container the engine builds gets a `/usr/bin/update`. Running it used to
mean one thing: pull `ct/<app>.sh` from the script repo and run it. That is still
the normal path, but it now goes through a helper first, because a script that
was removed upstream answered a raw 404 and a breaking change had no way to stop
anything.

## The entrypoint

`write_update_entrypoint()` in [`core/core.func`](../core/core.func) generates
`/usr/bin/update` on install and again after every successful update. It is a
generated file — editing it by hand is pointless, the next update overwrites it.

It bakes in the values that run needs, so the container keeps pulling from
whatever it was built from rather than from today's defaults:

| Exported | Meaning |
| -------- | ------- |
| `SCRIPT_SLUG` | The app's slug, for the website lookups |
| `UPDATE_SCRIPT_NAME` | The `ct/` script to pull |
| `COMMUNITY_SCRIPTS_URL` | Scripts root this container was built from |
| `COMMUNITY_SCRIPTS_CORE_URL` | Engine root, for the helper itself |
| `COMMUNITY_SCRIPTS_WEBSITE_URL` | Where the state lookups go |

The file is written to a temp name in the same directory and then `mv`'d into
place. `/usr/bin/update` is usually the script *currently running*, and it grows
from a one-liner to this — overwriting in place makes the running shell resume at
its old byte offset, now inside longer content, and execute garbage. `mv` gives
the new content a fresh inode, so the running shell reads the old one to a clean
EOF.

`migrate_update_entrypoint()` moves containers still carrying the old
direct-pull entrypoint onto the helper. It is safe to call on every update: it
does nothing if the helper is already in use, and it reads the script base out of
the legacy entrypoint rather than guessing from the current environment, so a
migrated container keeps pulling from the repo it always did.

## The helper

[`misc/update.sh`](../misc/update.sh) is the only file in `misc/`. It decides
whether the app can still be updated **before** any app script is pulled:

1. Ask the website — `/api/update-info?slug=<slug>` — for this app's state.
2. `active` or `disabled` → pull and run `ct/<name>.sh` exactly as before.
   Nothing about a normal update changes; the in-script guards below still run.
3. `deleted` or `unknown` → print the reason and do **not** pull. Add-ons are
   still offered, because they are independent scripts and keep working.
4. Website unreachable → fail open and attempt the normal update.

The entrypoint falls back to a direct pull if the helper itself cannot be
fetched, so `update` never becomes unusable because the engine repo is
unreachable.

## The two in-script guards

These run inside the app script, after it has been pulled — so they also cover
the case where someone runs the `ct/` one-liner by hand instead of `update`.

**`runtime_script_status_guard`** ([`ui/menu.func`](../ui/menu.func)) asks
PocketBase directly for `is_deleted`, `is_disabled`, `pinned_version` and
`pin_reason`. A deleted script stops. A disabled one stops unless
`var_ignore_disable` is set. The check has a 2 s connect and 3 s total timeout,
and warns rather than blocking when it cannot reach the API.

**`check_breaking_change_guard`** ([`ui/menu.func`](../ui/menu.func)) asks
`/api/breaking-changes?slug=<slug>` for advisories a maintainer marked as
blocking. It fails open on any error — an unreachable advisory endpoint must
never block an update — and remembers what it has already shown in
`/usr/local/community-scripts/breaking-changes.seen`, so the same advisory does
not re-warn on every run. `var_ignore_breaking_changes` opts a fleet out
entirely.

Neither guard uses `jq`: it is not present on a bare Proxmox VE host, so both
parse the fixed-shape JSON with `sed`.

## Why the state lives on the website

The alternative was a file in the script repo that every container would have to
fetch and diff. Behind an endpoint, a maintainer can retire or flag a script
without a release, and a container built two years ago asks the same question a
container built today does.
