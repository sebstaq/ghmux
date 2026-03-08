# ghmux

`ghmux` is a path-aware wrapper for the GitHub CLI.

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

`ghmux` only routes `gh` account context.

It is not a general Git credential manager. `git clone`, `git fetch`, and
`git push` still depend on your Git transport setup, such as SSH config or
HTTPS credential helpers.

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
4. Create your config file in `~/.config/ghmux/config.sh`.

Example shim:

```bash
#!/usr/bin/env bash
set -euo pipefail

export GHMUX_REAL_GH=/usr/bin/gh
exec /path/to/ghmux/bin/ghmux "$@"
```

On most Linux systems, `~/.local/bin` is a good place for that shim.

## Auth Behavior

Inside a routed path, `ghmux` resolves the configured account token by calling:

```bash
gh auth token --hostname <host> --user <user>
```

That means the target account must already exist in your normal `gh` auth
store.

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
- This project assumes a Bash environment.
- `ghmux` does not currently manage Git transport credentials.
- Config is a sourced Bash file, so it should be treated as trusted local
  configuration.

## License

MIT
