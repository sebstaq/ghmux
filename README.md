# ghmux

`ghmux` is a path-aware router for GitHub CLI and GitHub HTTPS Git auth.

It lets plain `gh` commands use different GitHub accounts based on the current
working directory, without globally switching `gh auth` state and without shell
hooks that mutate your environment when you `cd`.

## What It Does

When `ghmux` is installed as your `gh` shim, each invocation:

1. Checks the current working directory.
2. Matches it against configured path prefixes.
3. Resolves the target GitHub account for that path.
4. Injects `GH_TOKEN` and `GITHUB_TOKEN` for that process only.
5. `exec`s the real `gh` binary with the original arguments.

There is no daemon and no background process.

## Scope

`ghmux` routes two related things:

- `gh` account context through `bin/ghmux`
- GitHub HTTPS credentials for raw `git` operations through
  `bin/git-credential-ghmux`

It is not a general Git credential manager for every host and protocol. SSH
setups and non-GitHub remotes are outside its scope.

## How Routing Works

Configuration lives outside the repo in:

- `$XDG_CONFIG_HOME/ghmux/config.sh`, or
- `~/.config/ghmux/config.sh`

Rules are Bash strings in this format:

```bash
"/absolute/path/prefix|host|github-username"
```

The longest matching path prefix wins.

Example:

```bash
#!/usr/bin/env bash

GHMUX_DEFAULT_HOST=github.com
GHMUX_DEFAULT_USER=

GHMUX_RULES=(
  "$HOME/src/work|github.com|work-account"
  "$HOME/src/client-a|github.com|client-a-bot"
)
```

If no rule matches and `GHMUX_DEFAULT_USER` is empty, `ghmux` passes through
to the normal `gh` account state without injecting a token.

See [`examples/config.sh.example`](examples/config.sh.example).

## Install Locally

`ghmux` is shell-first. The simplest local setup is:

1. Put this repo somewhere stable.
2. Add a small `gh` shim earlier in `PATH` than the real `gh`.
3. Point that shim at `bin/ghmux`.
4. Add a Git `includeIf "gitdir:..."` rule for the path tree that should use
   `git-credential-ghmux`.
5. Create your config file in `~/.config/ghmux/config.sh`.

Example shim:

```bash
#!/usr/bin/env bash
set -euo pipefail

export GHMUX_REAL_GH=/usr/bin/gh
exec /path/to/ghmux/bin/ghmux "$@"
```

On most Linux systems, `~/.local/bin` is a good place for that shim.

Example Git config for a routed path tree:

```gitconfig
[includeIf "gitdir:/path/to/worktrees/"]
    path = ~/.gitconfig-devops-repos
```

Example included config:

```gitconfig
[user]
    name = work-account
    email = 123456+work-account@users.noreply.github.com

[credential "https://github.com"]
    helper =
    helper = !/path/to/ghmux/bin/git-credential-ghmux
```

## AI Setup Prompt

Alternatively, you can copy this prompt to your AI coding assistant to set up
`ghmux` on a machine:

> Set up ghmux for this machine using the repo docs and code.
> 1. Put the ghmux checkout in a stable path and use absolute paths everywhere.
> 2. Create `~/.config/ghmux/config.sh` with path-prefix routing rules in the format `"/absolute/path|host|github-username"`.
> 3. Install a `gh` shim earlier in `PATH` than the real `gh`, and make it exec `bin/ghmux`.
> 4. Add Git `includeIf "gitdir:..."` config for each routed path tree, and point the included config at `bin/git-credential-ghmux`.
> 5. Preserve the user’s normal global Git identity and GitHub credentials outside the routed paths.
> 6. Do not use shell hooks that mutate `GH_TOKEN`, `GITHUB_TOKEN`, or `GIT_CONFIG_GLOBAL` on `cd`.
> 7. Verify `gh auth status` inside and outside the routed paths.
> 8. Verify `git var GIT_AUTHOR_IDENT` and `git credential fill` inside and outside the routed paths.
> 9. If the project has AGENTS.md, CLAUDE.md, or CONTRIBUTING.md guidance for GitHub account usage, update it to mention ghmux.

## Auth Behavior

Inside a routed path, `ghmux` resolves the configured account token by calling:

```bash
gh auth token --hostname <host> --user <user>
```

That means the target account must already exist in your normal `gh` auth
store.

For raw `git` over HTTPS, `git-credential-ghmux` returns credentials in Git's
credential-helper protocol using the same routed account.

## Guardrails

In a routed context, these commands are blocked because they are misleading when
token injection is active:

- `gh auth login`
- `gh auth logout`
- `gh auth switch`

Use one of these when you intentionally want to manage global `gh` auth state:

```bash
GHMUX_BYPASS=1 gh auth login
/usr/bin/gh auth login
```

`gh auth status` is allowed and shows the effective routed identity.

## Development

Run the test suite:

```bash
./test/test-ghmux.sh
```

Or:

```bash
make test
```

## Limitations

- Anything that calls `/usr/bin/gh` directly bypasses `ghmux`.
- Anything that uses a Git credential helper other than `git-credential-ghmux`
  bypasses the routed GitHub HTTPS behavior.
- This project assumes a Bash environment.
- Config is a sourced Bash file, so it should be treated as trusted local
  configuration.

## License

MIT
