# Testing builds and feedback

Back to the [index](README.md).

A script under test is only worth testing if the results come back. Over one
week, 5800 installs from the testing repository produced feedback on 3 of 77
scripts — and a warning was already printed on every login, so the problem was
never visibility. It was that reporting meant working out where to go and what
to write.

`var_testurl` answers the first half: the script names the thread its feedback
belongs in.

## Using it

One line in the `ct/` script, in the same pattern as the other variables:

```bash
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2135}"
```

Anything else follows from that.

## What it changes

| `REPO_SOURCE` | `var_testurl` | Result |
| ------------- | ------------- | ------ |
| ProxmoxVED | unset | Generic development warning, links to the repository |
| ProxmoxVED | set | Names the thread, and does not name a repository |
| anything else | set | The same — a promoted script keeps collecting feedback |
| anything else | unset | Nothing |

The last row is the fix for a bug this replaced: the development warning used to
print unconditionally, so every Incus container was told on every login that it
was an unusable ProxmoxVED build.

Rows two and three deliberately drop the ProxmoxVED wording. A script promoted
to ProxmoxVE can still want feedback, and telling its users they are running a
development build would be wrong.

Because an unset variable changes nothing, scripts can be filled in one at a
time. There is no flag day.

## Where it shows up

- **MOTD**, on every login — `motd_ssh()` in [`lxc/install.func`](../lxc/install.func)
- **Container description**, visible in the Proxmox UI without logging in —
  `description()` in [`pve/backend.func`](../pve/backend.func)
- **Tag** `testing` alongside `community-script`, so the containers stay
  findable in the tree — [`ui/defaults.func`](../ui/defaults.func)
- **Last line of the install**, while the user is still watching

## Validation

`cs_testing_state()` in [`core/core.func`](../core/core.func) accepts only a
plain `https://` URL of at most 200 characters, from a narrow character set that
excludes `$`, backtick, parentheses, quotes, backslash and whitespace.

That is not paranoia about a hostile script — a `ct/` script is arbitrary bash
already. It is about where the value ends up. The MOTD is a shell script
generated through an *unquoted* heredoc, so a `$(...)` in the value would
execute when it is written. The description is HTML, where a single quote breaks
out of the `href` attribute.

A value that fails the check produces a warning and falls back to the generic
message. It does not fail the build: a bad link is not worth losing a container
over.

## Two things left out on purpose

**Not in `VAR_WHITELIST`.** `var_testurl` is not settable from a `.vars` file.
It describes the script, not the user's preferences, and making it configurable
would mainly serve as a way to switch the request off.

**No live counters.** A progress bar of feedback received would mean an HTTP
call on every login: slow logins, failures in containers without internet, and a
dependency on a backend being up. The MOTD stays static text. Numbers belong on
the website, which already has the install data.
