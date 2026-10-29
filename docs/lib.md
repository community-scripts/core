# `lib/` — the helper library

Back to the [index](README.md).

This is what install scripts call. Source [`tools.func`](../lib/tools.func); it
sources the five parts below. Alpine is the exception: it loads
[`alpine.func`](../lib/alpine.func) instead, chosen by
[`lxc/install.func`](../lxc/install.func) from `OS_FAMILY`.

Adding or renaming a function here means regenerating [`API.txt`](../lib/API.txt)
in the same PR — CI compares against it.

## [`system.func`](../lib/system.func)

Packages and repositories: `install_packages_with_retry`,
`upgrade_packages_with_retry`, `prepare_repository_setup`, `setup_deb822_repo`,
`cleanup_tool_keyrings`, `manage_tool_repository`. Plus OS probes (`is_debian`,
`is_ubuntu`, `get_os_info`, `get_system_arch`), service handling
(`stop_all_services`, `safe_service_restart`, `enable_and_start_service`),
downloads with retry (`curl_with_retry`, `download_file`), the version
bookkeeping the `setup_*` helpers use (`cache_installed_version`,
`should_update_tool`, `verify_tool_version`), and temp-directory tracking that
cleans up on exit.

Retries exist because APT and network failures during an install are usually
transient; a single failure would otherwise abort a build that would have
succeeded on the next attempt.

## [`forge.func`](../lib/forge.func)

Releases from GitHub, GitLab and Codeberg behind one pair of entry points:

```bash
check_for_release        github   myapp  owner/repo
fetch_and_deploy_release gitlab   myapp  owner/repo  ...
```

The per-forge release names (`check_for_gh_release`,
`fetch_and_deploy_gl_release`, `fetch_and_deploy_codeberg_release`, ...) still
exist as one-line wrappers, so existing scripts keep working. Tags and branches
have their own helpers outside that pair: `fetch_and_deploy_gh_tag`,
`check_for_gh_tag`, `fetch_and_deploy_gl_tag`, `fetch_and_deploy_gh_branch`,
`check_for_gh_branch`.

Deploy modes: prebuilt release asset, source tarball, `.deb` package, or a
plain URL through `fetch_and_deploy_from_url`.

Both entry points keep a version stamp in `~/.<app>`. It is written when the
deploy finishes, so a build that fails afterwards leaves it at the new
version; the marker `~/.<app>.pending` beside it holds the version the run
started from and stays until a run that deployed exits cleanly.
`check_for_release` redoes the update while the marker exists, and both
helpers export `CS_PREVIOUS_VERSION`, the version from before the update,
which stays right on that redo. Prefer it over reading `~/.<app>` when a
migration depends on the old version.

## [`runtime.func`](../lib/runtime.func)

Language runtimes and the application-level installers: `setup_nodejs`,
`setup_uv`, `setup_php`, `setup_go`, `setup_ruby`, `setup_rust`,
`setup_java`, `setup_java_memory`, `setup_dotnet`, `setup_composer`, `setup_ffmpeg`,
`setup_imagemagick`, `setup_yq`, `setup_adminer`.

### Docker inside LXC

Inside an LXC container, Docker gives each container a fresh procfs, so the
lxcfs mounts on `/proc/meminfo` and friends never reach it: nested containers
see the physical host's memory instead of the CT's limit. Limits are still
enforced, but anything that sizes itself from those numbers (JVM heap, Node, Go,
OpenMP thread pools) gets OOM-killed instead of staying within them.

`setup_docker` can fix this. It is off by default; enable it with
`DOCKER_LXCFS_VISIBILITY=yes` (or `true`), or the app variable
`var_docker_lxcfs=yes`. When enabled, it registers `/usr/local/bin/runc-lxcfs` as
Docker's `default-runtime`. On each container create, the wrapper binds the lxcfs
files into the container. If the container sets no memory limit, the wrapper
also applies the CT's limit to its cgroup, which musl and Node's
`uv_get_constrained_memory()` read. CPU needs nothing extra: `cpuset` is
inherited, and `/sys/devices/system/cpu/online` is bound for glibc's
`_SC_NPROCESSORS_ONLN`.

- It is a no-op, with a warning, outside LXC or where lxcfs is not mounted.
- It never replaces an existing `default-runtime` (e.g. `nvidia`). It never
  overrides an explicit `--memory` / `mem_limit`.
- On an update it only runs when explicitly requested. Without the variable,
  `daemon.json` is left as it is. With it, a running Docker is reloaded
  (`SIGHUP`) so the new default runtime applies without a restart.
- Setup leaves Docker untouched when `runc` or `jq` is missing or `daemon.json`
  cannot be parsed. If the wrapper cannot patch a container's config, it hands
  that config to runc unmodified.
- Use `docker run --runtime=runc` (compose: `runtime: runc`) to bypass it for one
  container.
- The limit is written at container creation. After `pct set` changes the CT's
  memory, existing containers keep the old value until they are recreated, or
  until `docker update --memory=<new> --memory-swap=<new> <container>`.
- **Monitoring containers are affected.** lxcfs reports *usage* from the
  reading process's own cgroup. A container that graphs "system memory used"
  from `/proc/meminfo` (gopsutil-based tools such as netdata, glances, Arcane's
  live stats) therefore shows only its own footprint. Total is correct, but
  free, available and cached memory are not. Run those containers with
  `runtime: runc`. Tools that read the Docker API instead (Portainer's
  dashboard, Arcane's Docker info panel) are unaffected, and `/proc/stat` (CPU)
  is not cgroup-scoped.

### Java inside LXC

Proxmox sets a CT's memory limit one cgroup above the CT's cgroup root, so
inside the CT `memory.max` reads `max`. The JVM then finds no container limit
and sizes its heap from the host's RAM: a 2 GB CT on a 48 GB host gets a 12 GB
default heap, and `-XX:MaxRAMPercentage=75` gives 36 GB. Incus exposes the limit
at the CT's cgroup root, where the JVM finds it on its own.

`setup_java_memory <unit>...` gives each systemd unit a drop-in,
`/etc/systemd/system/<unit>.service.d/java-memory.conf`. On every start it reads
`MemTotal` from `/proc/meminfo`, which lxcfs reports as the CT's limit, and
passes it as `JAVA_TOOL_OPTIONS=-XX:MaxRAM=<kB>k`. Call it after creating the
unit in the install script and again in `update_script` so existing installs
get it.

- `MaxRAM` only replaces the RAM figure the JVM's defaults are computed from.
  `-XX:MaxRAMPercentage`, `-Xmx` and an explicit `-XX:MaxRAM` on the command
  line still apply and win over it.
- After `pct set --memory`, restarting the service is enough.
- It is a no-op unless `/sys/fs/cgroup/memory.max` reads `max`, lxcfs serves
  `/proc/meminfo` and systemd runs, so it leaves Incus, VMs and Alpine alone.
- It owns `JAVA_TOOL_OPTIONS` for the unit: a value set with `Environment=` in
  the unit is replaced.

## [`db.func`](../lib/db.func)

`setup_postgresql`, `setup_mysql`, `setup_mariadb`, `setup_mongodb`,
`setup_clickhouse`, `setup_meilisearch`, and the `setup_*_db` helpers that
create a database and user.

## [`hwaccel.func`](../lib/hwaccel.func)

`setup_hwaccel` plus GPU detection and per-vendor setup for Intel (modern,
legacy and Arc), AMD (including APU and ROCm) and NVIDIA, and the device
permissions that go with them.

## [`alpine.func`](../lib/alpine.func)

The Alpine equivalent, written for `ash` rather than bash, with fallbacks for
the `msg_*` functions in case `core.func` was not loaded.
