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
downloads with retry (`curl_with_retry`, `download_file`), and temp-directory
tracking that cleans up on exit.

Retries exist because APT and network failures during an install are usually
transient; a single failure would otherwise abort a build that would have
succeeded on the next attempt.

## [`forge.func`](../lib/forge.func)

Releases, tags and branches from GitHub, GitLab and Codeberg behind one pair of
entry points:

```bash
check_for_release        github   owner/repo
fetch_and_deploy_release gitlab   owner/repo  ...
```

The per-forge names (`check_for_gh_release`, `fetch_and_deploy_gl_release`,
`fetch_and_deploy_codeberg_release`, and the tag and branch variants) still
exist as one-line wrappers, so existing scripts keep working.

Deploy modes: prebuilt release asset, source tarball, `.deb` package, or a
plain URL through `fetch_and_deploy_from_url`.

## [`runtime.func`](../lib/runtime.func)

Language runtimes and the application-level installers: `setup_nodejs`,
`setup_uv`, `setup_php`, `setup_go`, `setup_ruby`, `setup_rust`,
`setup_java`, `setup_dotnet`, `setup_composer`, `setup_ffmpeg`,
`setup_imagemagick`, `setup_yq`, and the version bookkeeping around them
(`cache_installed_version`, `should_update_tool`, `verify_tool_version`).

## [`db.func`](../lib/db.func)

`setup_postgresql`, `setup_mysql`, `setup_mariadb`, `setup_mongodb`,
`setup_clickhouse`, `setup_meilisearch`, `setup_adminer`, and the
`setup_*_db` helpers that create a database and user.

## [`hwaccel.func`](../lib/hwaccel.func)

`setup_hwaccel` plus GPU detection and per-vendor setup for Intel (modern,
legacy and Arc), AMD (including APU and ROCm) and NVIDIA, and the device
permissions that go with them.

## [`alpine.func`](../lib/alpine.func)

The Alpine equivalent, written for `ash` rather than bash, with fallbacks for
the `msg_*` functions in case `core.func` was not loaded.
