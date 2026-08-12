# How loading works

Back to the [index](README.md).

The engine and the scripts live in different repositories, so both are resolved
independently. A CT script bootstraps the engine with one line, and everything
after that goes through the resolver in [`core/build.func`](../core/build.func).

## Two roots

| Path prefix | Resolves against | Example |
| ----------- | ---------------- | ------- |
| `core/`, `ui/`, `lib/`, `lxc/`, `host/`, `api/`, `vm/`, `pve/`, `incus/` | **engine root** | `pve/backend.func` → `core/pve/backend.func` |
| everything else | **scripts root** | `install/debian-install.sh` → `ProxmoxVE/install/debian-install.sh` |

Paths are folder-qualified, so the prefix alone decides the root and there is no
name-to-folder map to keep in sync. It is also what lets files share a basename:
`incus/build.func` and `core/build.func` coexist because nothing resolves by
basename.

Deriving the scripts root from the calling script rather than from the engine
location is deliberate — conflating the two is what used to break local
`install/` lookups.

## Resolution order

1. **Local checkout** — used when found, so development needs no network at all
2. **Git origin** — a checkout's own remote and branch become its raw base, so a
   fork or branch is picked up automatically
   ([`host/source-origin.func`](../host/source-origin.func))
3. **Defaults** — `community-scripts/core@main` for the engine,
   `community-scripts/ProxmoxVED@main` for the scripts

## Environment variables

| Variable | Root | Purpose |
| -------- | ---- | ------- |
| `COMMUNITY_SCRIPTS_CORE_DIR` | engine | Local core checkout |
| `COMMUNITY_SCRIPTS_CORE_URL` | engine | Raw base for the engine |
| `COMMUNITY_SCRIPTS_ROOT` | scripts | Local script-repo checkout |
| `COMMUNITY_SCRIPTS_URL` | scripts | Raw base for the scripts |
| `COMMUNITY_SCRIPTS_DIR` | engine | Back-compat alias for `…_CORE_DIR` |
| `COMMUNITY_SCRIPTS_NO_PREFETCH` | — | Set to `1` to disable the prefetch |
| `LXC_PLATFORM` | — | Force `pve`, `incus`, `incus-container` or `container` (debugging) |

## The prefetch

Loading the engine one file at a time meant one HTTP request per file, and the
delay was visible before the header even appeared. Instead,
`_cs_prefetch_engine` pulls every file listed in `_CS_ENGINE_FILES` concurrently
with `curl --parallel` into `/dev/shm`, so the whole engine arrives in a single
round trip. Subsequent `_cs_source_func` calls read from there.

This is a transient prefetch, not a cache: no TTL, nothing to invalidate, and
stale directories from interrupted runs are swept on the next start.

A container has its own filesystem, so the host's copy cannot help it.
[`lxc/install.func`](../lxc/install.func) does the same thing on its side for the
smaller subset a container needs, listed in `_CS_CT_ENGINE_FILES`.

CI checks both lists against what is on disk, so a new file cannot be forgotten.
Missing one would not break anything — it would just cost a round trip nobody
would notice, which is exactly why it is checked rather than trusted.

## Platform detection

| Environment | Detected by | Backend |
| ----------- | ----------- | ------- |
| Proxmox VE host | `pveversion` present | `pve/backend.func` |
| Incus host | `incus` CLI and a reachable daemon | `incus/build.func` |
| Inside an Incus container | `/dev/incus/sock` or the Community Scripts MOTD | update mode |

Override with `LXC_PLATFORM` when debugging. See
[`lxc/platform.func`](../lxc/platform.func).

Host tools are the one thing that cannot be shared: `tools/pve/` scripts in the
ProxmoxVE repository call `pve*` binaries, and their Incus counterparts live in
the Incus repository.

## Running against a fork

Because the two roots are independent, either side can be swapped without
touching the other.

**Local checkouts** — clone core next to the script repo and run a script. No
configuration, no network:

```bash
git clone https://github.com/YOU/core
git clone https://github.com/YOU/ProxmoxVE
cd ProxmoxVE && bash ct/debian.sh
```

**Remote fork, engine only** — production scripts against your core branch:

```bash
export COMMUNITY_SCRIPTS_CORE_URL=https://raw.githubusercontent.com/YOU/core/my-branch
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/debian.sh)"
```

**Remote fork, scripts only** — `COMMUNITY_SCRIPTS_URL` has to be set here, and
it is the step people miss:

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/YOU/ProxmoxVED/my-branch
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/debian.sh")"
```

Fetching the ct script from a fork does not tell the engine where that fork is.
With `bash -c "$(curl …)"` there is no file on disk, so the walk-up that finds
the scripts root has nothing to walk and `COMMUNITY_SCRIPTS_URL` falls back to
the default. The ct script would run from the fork and then look for its
`install/` counterpart in upstream main.

A private fork cannot be used this way at all: `_cs_download` sends no
authentication header, so `raw.githubusercontent.com` answers 404. Use a local
checkout for those.

**Remote fork, both sides** — [`tools/run.sh`](../tools/run.sh) sets both bases
and then runs a script from the script base:

```bash
curl -fsSL https://raw.githubusercontent.com/community-scripts/core/main/tools/run.sh |
  bash -s -- https://raw.githubusercontent.com/YOU/ProxmoxVE/my-branch ct/debian.sh \
             https://raw.githubusercontent.com/YOU/core/my-branch
```
