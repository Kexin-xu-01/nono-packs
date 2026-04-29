<p align="center">
  <img src="./assets/logo.png" alt="nono codex" width="600" />
</p>

# nono codex

Sandbox profile and Codex plugin for running [OpenAI Codex CLI](https://developers.openai.com/codex) inside a [nono](https://nono.sh) security sandbox.

Install:

```
nono run --profile codex -- codex
```

If the pack isn't already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** — sandbox profile (loaded as `--profile codex`). Grants `~/.codex`, `~/.agents`, `~/.config/nono/{profiles,packages}` (read-only), the OpenAI auth origin, and runtime groups for Node, Rust, Python, Nix.
- **`.codex-plugin/plugin.json`** — Codex plugin manifest, exposes the `nono-sandbox` skill.
- **`bin/nono-hook.sh`** — `PostToolUse` hook. When a Bash or apply_patch tool fails with a permission-denial signature, blocks the agent loop and surfaces a precise diagnostic (the boundary, the allowed paths, two remediation options).
- **`bin/nono-hook-permission.sh`** — `PermissionRequest` hook. Denies upstream when Codex's approval flow asks for something nono won't grant — Codex's "yes" can't override the OS sandbox.
- **`bin/nono-hook-session.sh`** — `SessionStart` hook. Pre-loads the sandbox boundary into the conversation so the model understands the limits from turn 1.
- **`skills/nono-sandbox/SKILL.md`** — skill describing how to diagnose and resolve sandbox denials.

## Activating the hooks

`nono pull always-further/codex` writes the marketplace registration, the hook entries, and the cache symlink, but leaves your `config.toml` alone — that file often contains user customisations and a clean TOML merge isn't worth the risk of clobbering them. After accepting the install prompt you'll see a one-line reminder if the flag isn't set.

## Known issues

Currently codex hooks are quite verbose, so you will see the following logged to the TUI:

```
• PostToolUse hook (blocked)
  warning: nono sandbox denial
  hook context: Sandbox denial.
.........
```

We are aware of this and it is being fixed in codex upstream (kudos OpenAI for being Open with your coding agent) - as soon as those can be toggled off, we will be getting this fixed.

## Source

`https://github.com/always-further/nono-packs/tree/main/codex`

Published via Sigstore-signed releases triggered by tags matching `codex-v*`.
