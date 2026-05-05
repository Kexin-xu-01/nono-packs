# nono hermes

Sandbox profile, Hermes plugin, and Hermes skill for running [Hermes Agent](https://hermes-agent.nousresearch.com/) inside a [nono](https://nono.sh) security sandbox.

Install:

```bash
nono run --profile hermes -- hermes
```

If the pack is not already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** — sandbox profile loaded as `--profile hermes`. Grants Hermes state under `~/.hermes`, nono user profile writes under `~/.config/nono/profiles`, read-only package metadata under `~/.config/nono/packages`, the Hermes launcher directory, and uv-managed Python runtimes under `~/.local/share/uv`.
- **`plugin/nono-sandbox/`** — Hermes plugin. It registers a `nono_status` tool, injects a first-turn sandbox boundary, and injects focused remediation context after tool calls that look like nono denials.
- **`skills/nono-sandbox/SKILL.md`** — Hermes-native skill explaining how to diagnose and fix nono sandbox denials.
- **`bin/nono-hermes-status.sh`** — small diagnostic script for checking Hermes, nono, current capabilities, and sensitive Hermes file permissions.
- **`templates/config-hardening.yaml`** — optional `~/.hermes/config.yaml` snippet for enabling the plugin, fail-closed Tirith scanning, URL blocking, and a `/nono-status` quick command.

## Activating the plugin

`nono pull always-further/hermes` symlinks the plugin into:

```text
~/.hermes/plugins/nono-sandbox
```

Hermes plugins are intentionally opt-in. Enable it with:

```bash
hermes plugins enable nono-sandbox
```

or merge this into `~/.hermes/config.yaml`:

```yaml
plugins:
  enabled:
    - nono-sandbox
```

The skill is symlinked into:

```text
~/.hermes/skills/nono/nono-sandbox
```

and is available as `/nono-sandbox` after Hermes reloads its skill index.

## Research notes

The pack maps directly to Hermes security features:

- Hermes approvals catch risky commands, but nono remains the outer OS boundary. The plugin therefore steers the agent toward `nono why` and profile changes instead of approval workarounds.
- Hermes skill metadata supports secure env-var declarations and credential-file declarations. The included skill deliberately declares neither; it should not increase secret exposure.
- Hermes plugin hooks are the right CLI+gateway surface for sandbox diagnostics. Gateway-only event hooks are useful for production monitoring, but this pack keeps them out of the default install to avoid surprise logging.
- Hermes supports online skills registries, direct URL installs, GitHub taps, and well-known skill endpoints. `registry.nono.sh` could be valuable as a curated nono-specific skill and pack registry if it keeps signed provenance, review metadata, and security-scan results rather than becoming an unreviewed skill dump.

## Source

`https://github.com/always-further/nono-packs/tree/main/hermes`

Published via Sigstore-signed releases triggered by tags matching `hermes-v*`.
