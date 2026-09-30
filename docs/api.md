# `api/` — telemetry

Back to the [index](README.md).

Source [`api.func`](../api/api.func); it sources the four parts below. Adding or
renaming a function means regenerating [`API.txt`](../api/API.txt) in the same
PR — CI compares against it.

## The one-event rule

Exactly one terminal event reaches the server per execution, and it comes from
the host. Code running inside a container sends only progress pings
(`post_progress_to_api` in [`lxc/install.func`](../lxc/install.func)), never a
terminal status: it writes `/root/.install-<SESSION_ID>.failed` and an
`.errinfo` capture, which the host picks up after `lxc-attach` returns. See
[`core/error_handler.func`](../core/error_handler.func).

## [`exitcodes.func`](../api/exitcodes.func)

`explain_exit_code` — the exit code table — and `categorize_error`. This is the
authoritative copy of the table; `core/error_handler.func` carries a fallback
for the container case where this file is not loaded.

## [`errorlog.func`](../api/errorlog.func)

Extracting the useful part of a failed run's log: `get_error_log`,
`get_error_text`, `get_full_log`, `write_errinfo`, `build_error_string`.

Which log to read is picked by `_tm_pick_logfile`: the combined install log,
then `INSTALL_LOG`, `BUILD_LOG`, `SILENT_LOGFILE`. The log a run writes to is
decided by `get_active_logfile` in [`core/core.func`](../core/core.func).

## [`sysinfo.func`](../api/sysinfo.func)

Facts about the machine and where the script came from: `detect_cpu`,
`detect_ram`, `detect_gpu`, `detect_arm`, `detect_repo_source`,
`telemetry_collect_sysinfo`.

## [`telemetry.func`](../api/telemetry.func)

Assembly and delivery. The public entry points:

| Function | When |
| -------- | ---- |
| `post_to_api` | An install starts |
| `post_to_api_vm` | Same, for a VM |
| `post_progress_to_api` | A step completed |
| `post_update_to_api` | Terminal status — success, failed, aborted |
| `post_tool_to_api` | A host tool ran |
| `post_addon_to_api` | An add-on ran |

Telemetry is opt-out through `/usr/local/community-scripts/diagnostics`.
