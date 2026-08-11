# Dev mode

Back to the [index](README.md).

Opt-in debugging, implemented in [`core/dev-mode.func`](../core/dev-mode.func).
Off unless asked for, so it costs nothing in a normal run.

## Flags

| Flag | Effect |
| ---- | ------ |
| `net` | Log every engine fetch: HTTP status, duration, URL |
| `timing` | Show how long each step took, and the slowest ones at the end |
| `trace` | `set -x` tracing |
| `pause` | Wait for a keypress after each step |
| `keep` | Never delete the container when a build fails |
| `breakpoint` | Open a shell on error instead of cleaning up |
| `motd` | Set up MOTD and SSH early, so a kept container can be inspected |
| `logs` | Persist all logs to `/var/log/community-scripts/` |

## Using it

Give the flags directly and they are used as-is:

```bash
dev_mode=net,timing,keep bash -c "$(curl -fsSL .../ct/onetimesecret.sh)"
```

Set `dev_mode` without a value — or to `1`, `yes`, `true`, `ask` or `menu` — and
a picker appears **before** the default/advanced dialog, so the choice is made
before anything is built:

```bash
dev_mode=1 bash -c "$(curl -fsSL .../ct/onetimesecret.sh)"
```

A dev run is red rather than green throughout, so it never reads as a normal
install by accident.

## What it prints

`dev_mode_context` reports where the engine came from — engine source, both
roots, both URLs, the app, the platform, the architecture and the versions
involved. With `timing`, `dev_mode_timing_summary` prints a per-step breakdown
at the end, and it runs from the `EXIT` trap so the numbers survive a failure.
