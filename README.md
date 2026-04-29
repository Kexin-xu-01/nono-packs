# nono-packs

`nono-packs` is the package and plugin registry for the `nono` ecosystem.

This repository is the source for installable packs that extend agent runtimes with `nono`-specific integrations such as:

- agent plugins
- hook definitions
- packaged skills
- support scripts and helper assets

Each top-level directory is an individual pack. Packs are described by a `package.json` manifest and can ship one or more artifacts that are installed into the target agent environment.

## Repository Layout

Current packs in this repository include:

- [`claude`](./claude): Claude Code integration for working inside the `nono` sandbox
- [`codex`](./codex): Codex integration for working inside the `nono` sandbox

Typical pack contents:

- `package.json`: pack manifest used by the registry
- `README.md`: pack-specific documentation
- `skills/`: packaged skills distributed with the pack
- `hooks/`: hook registrations for the target runtime
- `bin/`: executable helper scripts used by hooks or setup flows

## What This Registry Is For

The goal of this repository is to keep agent-facing integrations versioned, reviewable, and distributable separately from the core `nono` runtime.

That allows a pack to:

- teach an agent how to behave correctly inside the `nono` sandbox
- install runtime-specific hooks
- bundle skills and prompts that improve sandbox diagnostics
- ship small helper scripts without coupling them to the main `nono` repository

## Pack Format

Each pack should define:

- a unique `name`
- a `pack_type`
- a short `description`
- supported `platforms`
- a `min_nono_version`
- an `artifacts` list describing what should be installed

The exact artifact set depends on the target runtime. For example, a Claude-oriented pack can include Claude plugin metadata, hook definitions, and sandbox-awareness skills.

## Current Status

This repository is intended to host multiple packs, packages, and skills for the wider `nono` registry. The [`claude`](./claude) pack is the initial example and documents the expected structure for future additions.
