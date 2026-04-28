# openclaw nono Pack

`openclaw` is a `nono` package for running OpenClaw AI agents inside a nono security sandbox.

It ships a nono profile covering all standard OpenClaw instance directories, a skill that teaches agents their sandbox constraints, and a hook that fires contextual diagnostics on permission failures.

## What It Does

**Multi-instance filesystem coverage**

The built-in `openclaw` profile only allows `~/.openclaw`. Running a second or third agent instance (`~/.openclaw-agent1`, `~/.openclaw-agent2`) would otherwise be blocked. This pack's profile covers all standard instance directories so any agent variant runs without filesystem errors out of the box.

**Sandbox-aware diagnostics**

When a tool call hits a sandbox boundary, the installed hook detects the denial and injects the exact blocked path, the current capability set, and a ready-to-use profile template — so the agent presents the user with the two right options instead of guessing.

**Multi-agent coordination**

All sandboxed OpenClaw instances on the same machine share `$TMPDIR/openclaw-$UID/` as a lightweight coordination bus. This lets peer agents signal task ownership, share state, and avoid duplicate work without network calls or breaking sandbox isolation.

## Installation

Requires nono ≥ 0.44.0.

```bash
nono pull always-further/openclaw
```

## Usage

**Single agent**

```bash
nono run --profile openclaw -- openclaw
```

**Named agent instance**

```bash
nono run --profile openclaw --home ~/.openclaw-agent1 -- openclaw
```

## Included Artifacts

| Artifact | Type | Purpose |
|---|---|---|
| `policy.json` | `profile` | nono sandbox profile covering all standard OpenClaw directories and coordination bus |
| `skills/nono-sandbox/SKILL.md` | `plugin` | Teaches the agent its constraints and how to diagnose permission failures |
| `bin/nono-hook.sh` | `plugin` | Injects capability context and remediation options on permission denial |

## Policy Details

The profile:
- Extends `default` (inherits all standard security groups)
- Allows `~/.openclaw`, `~/.openclaw-agent1/2/3`, `~/.config/openclaw`, `~/.openclaw.json`
- Allows `$TMPDIR/openclaw-$UID` as the coordination bus
- Adds `node_runtime`, `linux_runtime_state`, `linux_sysfs_read`, `git_config` security groups
- Sets `ipc_mode: shared_memory_only`
- Network: not blocked
- Workdir: read-only
- Non-interactive

## Package Metadata

- Name: `openclaw`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
- Min nono version: `0.44.0`

## Directory Layout

```
openclaw/
├── .openclaw-plugin/
│   └── plugin.json
├── bin/
│   └── nono-hook.sh
├── package.json
├── policy.json
├── README.md
├── skills/
│   └── nono-sandbox/
│       └── SKILL.md
└── wiring/
    ├── enabled-plugin.json
    ├── installed-plugin.json
    ├── known-marketplaces.json
    └── marketplace.json
```
