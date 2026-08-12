# Contributing to core

Back to the [index](README.md).

Engine changes affect every script in the collection at once, so they get more
scrutiny than an application script does.

## Where does my change go?

| I want to… | Go here |
| ---------- | ------- |
| Change the engine | Open a PR here, and say which platforms you tested on |
| Add a new application script | [ProxmoxVED](https://github.com/community-scripts/ProxmoxVED) |
| Fix an existing application script | [ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) |
| Add Incus host tooling | [Incus](https://github.com/community-scripts/Incus) |
| Report a bug | [Issues](https://github.com/community-scripts/core/issues) — include your host platform and whether it reproduces on the other one |
| Ask a question | [Discord](https://discord.gg/3AnUqsXnmK) |

## Rules that CI enforces

`.github/workflows/verify-split-files.yml` checks all of these on every PR that
touches an engine folder.

**Loaders are the entry point, not the parts.** `lib/tools.func`,
`ui/build-ui.func` and `api/api.func` each source the files beside them. Source
the loader. If you add, rename or remove a function in any part, regenerate that
area's `API.txt` in the same PR — CI diffs the loader's actual function list
against it. This exists because a split can silently lose a function, most
easily by cutting through a heredoc that contains a column-0 function
definition: it looks like a definition but is payload, and the loss only shows
up on a user's host at install time.

**New files must be listed in the prefetch.** `_CS_ENGINE_FILES` in
`core/build.func` lists every engine file; `_CS_CT_ENGINE_FILES` in
`lxc/install.func` lists the subset a container needs. CI checks both against
what is on disk in both directions. A missing entry would not break anything —
it would just cost a round trip — which is exactly why it is checked instead of
trusted.

**Everything has to parse.** `bash -n` runs over every `.func`.

## Rules that CI cannot check

- **Test on both backends** when you touch anything outside `pve/` or `incus/`.
  A change that only works on Proxmox VE belongs in `pve/`.
- **Never hardcode a raw URL.** Use `_cs_source_func "<folder>/<name>.func"` so
  both roots keep resolving and forks keep working. See
  [loading.md](loading.md).
- **New files go in the folder that matches what they are.** Nothing resolves by
  basename, so `incus/tools.func` and `lib/tools.func` are both fine.
- **Run `shellcheck` and `shfmt`** on the files you touched.

## Line endings

Every file here is sourced by bash on Linux. A CRLF line ending makes the shell
read the carriage return as part of the token, which turns `load_functions() {`
into a syntax error and takes the whole engine with it — nothing would install.
`.gitattributes` forces LF on the way in, so this cannot happen by accident.

## Testing a change

Every pull request that touches an engine folder gets a comment with the exact
command to run a script against that branch — `.github/workflows/pr-test-command.yml`
assembles it from the PR's own head repository and branch. ProxmoxVED does the
same for the scripts it touches. So reviewing a change starts with a copy and a
paste, not with building URLs by hand.

The fastest loop for your own work is two local checkouts side by side — no network, no
configuration:

```bash
git clone https://github.com/YOU/core
git clone https://github.com/YOU/ProxmoxVE
cd ProxmoxVE && bash ct/debian.sh
```

For anything touching the error path or the install flow, run it against a real
container rather than trusting the read. [dev-mode.md](dev-mode.md) covers the
flags that make that practical — `keep` to stop a failed build from deleting its
evidence, `net` to see every fetch, `timing` to see where the time went.
