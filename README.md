# sfb - Smart File Browser (macOS)

`sfb` is a shell-based, Homebrew-ready smart file browser for macOS with:
- Interactive TUI flow (via `fzf`) for disk-usage triage
- Agent-friendly CLI/JSON interface
- Trash-only deletion flow with strong guardrails

## Features

- Fast disk usage scans (`scan`, `list`)
- Recursive usage summary (`summary`)
- Name-based search with safety filtering (`find`)
- Interactive full-screen TUI (`sfb` or `sfb tui`) with loading indicators
- Protected path policy (system roots + home-critical dirs)
- Two-key delete authorization for CLI/agent use:
  - `--allow-delete`
  - `--unlock-token <token>` from `sfb unlock`
- Trash-only delete behavior (`trash` command, never `rm`)

## Install (Homebrew)

```bash
brew tap henkas/tap
brew install henkas/tap/sfb
```

## Install (local)

```bash
chmod +x bin/sfb
./bin/sfb doctor --install-deps
```

Then optionally add to your PATH:

```bash
ln -sf "$(pwd)/bin/sfb" /usr/local/bin/sfb
```

## Usage

```bash
sfb
sfb tui ~/Downloads
sfb scan ~ --depth 2 --top 50
sfb scan ~ --depth 2 --top 50 --human
sfb list ~/Projects --json
sfb list ~/Projects --human
sfb summary ~/Projects --json
sfb find ~/Projects --name '*.log' --json
token="$(sfb unlock)"
sfb trash ~/Downloads/big.iso --allow-delete --unlock-token "$token"
```

## Commands

- `sfb` or `sfb tui [path]`
- `sfb scan [path] [--depth N] [--top N] [--human] [--json|--tsv]`
- `sfb list [path] [--top N] [--sort size|name] [--human] [--json|--tsv]`
- `sfb summary [path] [--json]`
- `sfb find [path] [--name PATTERN] [--json]`
- `sfb trash <path...> [--allow-delete --unlock-token TOKEN] [--json]`
- `sfb doctor [--install-deps] [--issue-token] [--json]`
- `sfb unlock`
- `sfb protect list|add|remove`

## Guardrails

Immutable hard-protected paths:
- `/`, `/System`, `/usr`, `/bin`, `/sbin`, `/private`, `/dev`, `/etc`, `/var/db`

Home-critical protected paths (high-risk):
- `~/Library`, `~/.ssh`, `~/.gnupg`, `~/.config`, `~/.local/share`

By default, high-risk paths are blocked from delete operations unless explicitly unprotected in config.

## Config

Config file: `~/.config/sfb/config`

Supported keys:
- `SFB_EXTRA_PROTECTED_PATHS=/path/a:/path/b`
- `SFB_UNPROTECTED_PATHS=/path/c`
- `SFB_ALLOW_HIGH_RISK_DELETE=0`
- `SFB_TOKEN_TTL_SECONDS=600`

## Development

Run syntax checks:

```bash
bash -n bin/sfb lib/*.sh
```

Run tests (Bats):

```bash
bats tests/sfb.bats
```
