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

Telemetry starts with the install record (`post_to_api`, `post_to_api_vm`),
which the build sends once the checks and dialogs are behind it. A run that
ends before that sends nothing: a host that is not ready is not a failed
install. Tools and add-ons have no such point, so a failure with a
"requirement not met" code (10, 103, 104, 106, 232, 233, 234, 236, 238) sends
nothing either. Update runs inside a container send nothing.

The checks, the settings and the storage dialogs wait on `pveversion`,
`pvesm status` (all, `vztmpl`, `rootdir`), `pveam available` and `pvesh`.
`core/build.func` starts these in the background before it downloads the
engine, `variables` adds pve-container's verdict on the release, and the
readers take them through `_cs_probe_read` / `_cs_probe_rc` (`_pvesm_status`
for storage). `_offer_storage_content` and `_pveam_update` drop what they
change with `_cs_probe_drop`. Guest IDs are checked against the configs under
`/etc/pve/nodes`, which pmxcfs keeps for every node.

## What a failure carries (payload version 3)

| Field | Source |
| ----- | ------ |
| `error_message` | The first `msg_error` of the failing step. Empty when the engine printed none; the server then picks a line from the trace. |
| `error_step` | The last `msg_info` text, or `after <msg_ok text>` between steps. |
| `error_phase` | `host` or `container`. |
| `failed_command`, `failed_line`, `failed_function` | The command that failed. A helper's `return N` is replaced by the call on that line, and a `silent()` failure a helper passed up keeps its own command. |
| `error` | `exit_code=N \| <explanation>[ \| step: …][ \| in …][ \| at line L: …]`, then `---` and the failing command's output, or the failing step's log lines, with package and download progress removed. |

`core.func` tracks the step (`CS_STEP`, `CS_STEP_DONE`) and the message
(`CS_ERROR_MSG`); the capture format is described at the top of
[`errorlog.func`](../api/errorlog.func).

## [`exitcodes.func`](../api/exitcodes.func)

`explain_exit_code` — the exit code table — and `categorize_error`. The one copy
of the table: the container loads this file too. The table borrows curl's and
APT's numbering, so the explanation (`_eh_explanation` in the error handler)
names the program that failed when it is not that tool, and `categorize_error`
files `systemctl` and `pct`/`qm` failures under their own categories.

## [`errorlog.func`](../api/errorlog.func)

The capture and the trace: `_tm_clean_log` (the noise filter, `_TM_NOISE`),
`_tm_step_output`, `_tm_error_context`, `build_error_string`. Loaded by the
container as well, for `silent()` and the error handler.

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

They run with errexit and the caller's ERR trap off (`_tm_quiet`), so a failing
command in here never reaches the error handler.

Telemetry is opt-out through `/usr/local/community-scripts/diagnostics`.
`TELEMETRY_URL` overrides the endpoint on the host and in the container.
