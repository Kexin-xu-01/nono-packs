# opencode nono

`opencode` is a `nono` package for [opencode](https://github.com/opencode-ai/opencode).

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox.

## What It Does

This pack solves one problem: when opencode hits a sandbox boundary, it should stop guessing and explain the real fix.

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that detects denial signatures in tool results and appends capability context + Option A/B remediation guidance
- a `nono-sandbox` skill that teaches the correct diagnostic flow

## Behavior

When opencode is running inside a `nono` sandbox and a tool call fails due to blocked filesystem or network access, the installed plugin:

- no-ops if `NONO_CAP_FILE` is not set (i.e. not inside a nono session)
- detects sandbox-denial signatures in tool results (`Operation not permitted`, `EACCES`, `EPERM`, `landlock`)
- appends the active capability set and remediation instructions so the model always receives the correct guidance
- steers the model toward the two valid remediations: `--allow` restart or a persistent profile draft

This prevents common bad guidance such as retrying the same action, suggesting `chmod`, or treating the failure as a macOS TCC issue.

## Install

```bash
nono pull always-further/opencode
```

Or let nono prompt you on first use:

```bash
nono run --profile opencode -- opencode
```

## Activation

After pulling, opencode reads the plugin from `~/.config/opencode/plugins/nono-sandbox.ts` and the skill from `~/.config/opencode/skills/nono-sandbox/SKILL.md`. Both are symlinked from the pack store; they update automatically on `nono pull`.

## Removing

```bash
nono remove always-further/opencode
```

## Package Metadata

- Name: `opencode`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
