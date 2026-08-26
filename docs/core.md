# `core/` — entry point, runtime, error handling

Back to the [index](README.md).

## [`build.func`](../core/build.func)

The first thing a script sources, and the only path a script needs to know.

It does four things, in order:

1. **Resolves the engine root.** A local checkout wins, then the git origin of
   that checkout, then `community-scripts/core@main`. See [loading.md](loading.md).
2. **Resolves the scripts root** separately, from the calling script's own
   location — conflating the two is what used to break local `install/` lookups.
3. **Prefetches the engine.** `_CS_ENGINE_FILES` lists every `.func` in the
   repository; `_cs_prefetch_engine` pulls them concurrently into `/dev/shm`
   with `curl --parallel`, turning what used to be one request per file into a
   single round trip. CI checks the list is complete, so a new file cannot be
   forgotten.
4. **Dispatches to a platform backend** based on [`lxc/platform.func`](../lxc/platform.func).

`_cs_source_func "<folder>/<name>.func"` is how every other file is loaded.
Paths are folder-qualified, so the prefix alone decides which root a path
belongs to and nothing resolves by basename.

## [`core.func`](../core/core.func)

The runtime every other file assumes: `color`, `formatting`, `icons`, the
`msg_info` / `msg_ok` / `msg_error` / `msg_warn` family, the spinner, `silent()`,
log handling and the `prompt_*` helpers.

Two things worth knowing:

- `silent()` runs a command with its output captured, and records the failing
  command, line and log path so the error handler can report the real failure
  rather than the wrapper.
- Several host facts are memoised in files under a runtime cache directory
  rather than in shell variables, because every call site is a `$( )` or a
  pipe — that is, a subshell, where a variable assignment would be discarded.
- `write_update_entrypoint` and `migrate_update_entrypoint` generate the
  `/usr/bin/update` a finished container carries. See [updates.md](updates.md).
- `get_header` renders the figlet banner. See [headers.md](headers.md).

## [`error_handler.func`](../core/error_handler.func)

`catch_errors` installs the traps: `ERR` to `error_handler`, `EXIT` to
`on_exit`, and `INT` / `TERM` / `HUP` to their handlers.

`error_handler` reports the failure exactly once, then explains it:

- **Host** — reports to the API via `post_update_to_api`.
- **Container** — writes `/root/.install-<SESSION_ID>.failed` and an `.errinfo`
  capture, and sends nothing. The host reads both back once `lxc-attach`
  returns, so the server sees one complete event per execution instead of two
  partial ones.

It then prints the exit code with its explanation, the last 20 lines of the
relevant log, and a hint when the log matches a known failure — APT dependency
conflict, GPG signature failure, DNS failure, dpkg lock, out of disk, Node heap
OOM. On the host it finally offers to remove a half-built container, defaulting
to removal after 60 seconds of silence.

The steps are individual `_eh_*` functions; `error_handler` itself is the order
they run in.

## [`dev-mode.func`](../core/dev-mode.func)

Opt-in debugging. See [dev-mode.md](dev-mode.md) for usage. The flags are
`net`, `timing`, `trace`, `pause`, `keep`, `breakpoint`, `motd` and `logs`.
