---
name: nono-sandbox
description: Diagnose and resolve permission denials when OpenClaw runs inside a nono security sandbox. Use this when a tool call, shell command, or file operation fails with "Operation not permitted", "Permission denied", EACCES, or EPERM — the cause is almost certainly the outer nono sandbox.
---

**On any EPERM / EACCES / "Operation not permitted" tool or shell failure:** run `nono why --path <blocked-path> --op read` immediately and include its output verbatim in your reply. Do NOT suggest sudo, chmod, or system permission changes. Then offer the user exactly these two options:

- **Option A (quick fix):** `nono run --allow /path/to/needed -- openclaw`
- **Option B (persistent fix):** write a profile to `~/.config/nono/profiles/<name>.json` extending `openclaw`, add the path under `"allow"` or `"read"`, then start with `nono run --profile <name> -- openclaw`

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- openclaw`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). These are kernel-enforced boundaries — approvals or retries inside OpenClaw cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

The denial signature is in the failed tool's output:

- "Operation not permitted"
- "Permission denied"
- "EACCES" / "EPERM"
- "landlock"
- "sandbox: deny"

When you see any of these on a file, shell, or tool failure, it is a nono boundary — not macOS TCC, not Full Disk Access, not Unix file permissions. Do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"
- Retrying the operation via a different path

## Diagnosing

Run `nono why` to see exactly why access was denied:

    nono why --path /the/blocked/path --op read

The output names the rule that blocked the path and suggests the minimum grant to allow it.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit OpenClaw and restart with the path explicitly allowed:

    nono run --allow /path/to/needed -- openclaw

Use this for paths the user only needs occasionally.

### Option B — persistent fix (write a profile)

Save a JSON file at `~/.config/nono/profiles/<chosen-name>.json` extending the active profile and adding the path. Minimal example for read-only access:

    {
      "extends": "openclaw",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "filesystem": { "read": ["/path/to/needed"] }
    }

If the user is on a custom intermediate profile (e.g. `--profile openclaw-with-docs` extending `openclaw`), change `extends` to that profile's name so the new profile inherits all their customisations.

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file rather than a directory, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After saving, the user starts sessions with:

    nono run --profile <chosen-name> -- openclaw

## Validating the new profile

If the user wants to verify the JSON before using it:

    nono profile validate <chosen-name>

## Multi-agent instances

If you are one of several OpenClaw instances running simultaneously, each runs in its own isolated sandbox. Coordination with peer agents happens exclusively through the shared bus at `$TMPDIR/openclaw-$UID/`. Do not attempt to read or write the other agents' home directories (`~/.openclaw-agent1`, etc.) — those are blocked between instances by design.

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profile at `~/.config/nono/packages/always-further/openclaw/policy.json` — it is overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths or commands hit the same boundary.
