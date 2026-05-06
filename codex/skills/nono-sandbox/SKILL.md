---
name: nono-sandbox
description: Diagnose and resolve permission denials when Codex runs inside a nono security sandbox. Use this when a Bash command, apply_patch, or MCP tool fails with "Operation not permitted", "Permission denied", EACCES, or EPERM — the cause is almost certainly the outer nono sandbox.
---

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- codex`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). Approval flows inside Codex cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

The denial signature is in the failed tool's output:

- "Operation not permitted"
- "Permission denied"
- "EACCES" / "EPERM"
- "landlock"
- "sandbox: deny"

When you see any of these on a Bash, apply_patch, or MCP file-tool failure, it is a nono boundary — not macOS TCC, not Full Disk Access, not Unix file permissions, not a Codex approval. Do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"
- Bypassing with `--dangerously-skip-permissions`

## Diagnosing

Run `nono why` to see exactly why access was denied:

    nono why --path /the/blocked/path --op read

The output names the rule that blocked the path and suggests the minimum grant to allow it.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit Codex and restart with the path explicitly allowed:

    nono run --allow /path/to/needed -- codex

Use this for paths the user only needs occasionally.

### Option B — persistent fix (draft a profile)

The active profile directory `~/.config/nono/profiles/` is read-only from inside the sandbox by design. Drafts are written to `~/.config/nono/profile-drafts/` and the user promotes them out-of-band with `nono profile promote`.

Write the JSON to `~/.config/nono/profile-drafts/<chosen-name>.json` extending the active profile. Minimal example for read-only access:

    {
      "extends": "codex",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "filesystem": { "read": ["/path/to/needed"] }
    }

If the user is on a custom intermediate profile (e.g. `--profile codex-with-docs` extending `codex`), change `extends` to that profile's name so the new profile inherits all their customisations.

If a user profile of that name already exists, read `~/.config/nono/profiles/<chosen-name>.json` first, compute the SHA-256 of the exact bytes you read, base your edit on that profile, write the full proposed profile to `~/.config/nono/profile-drafts/<chosen-name>.json`, and write the hash to `~/.config/nono/profile-drafts/<chosen-name>.base`.

If there is no user profile yet and the active profile is pack-provided or built-in, do not draft a replacement with the same name. Draft a derived profile such as `<active>-local` with `"extends": "<active>"` and add only the extra access there.

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file rather than a directory, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After drafting, tell the user:

    Drafted profile <chosen-name>. Run `nono profile promote <chosen-name>` to review and apply, then start sessions with `nono run --profile <chosen-name> -- codex`.

## Validating the new profile

`nono profile promote` shows a diff and validates before applying. If the user wants to validate the draft directly:

    nono profile validate --draft <chosen-name>

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profile at `~/.config/nono/packages/always-further/codex/policy.json` — it's overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths or commands hit the same boundary.
