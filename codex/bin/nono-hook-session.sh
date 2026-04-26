#!/bin/bash
# nono-hook-session.sh - Codex SessionStart hook
# Version: 1.0.0
#
# Pre-loads the nono sandbox boundary into the conversation so Codex
# understands the limits from turn 1 and won't reach for "macOS TCC" or
# "chmod" diagnoses on the first denial.
#
# Schema reference:
#   https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/session-start.command.output.schema.json

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

CONTEXT="You are running inside a nono security sandbox. Filesystem and network access is enforced at the OS level (Landlock on Linux, Seatbelt on macOS) — there is NO escape from inside the session.

Allowed paths:
$CAPS
Network: $NET

When a tool call fails with \"Operation not permitted\", \"Permission denied\", EACCES, or EPERM, the cause is this sandbox boundary — not a Codex permission, not macOS TCC, not Unix file permissions. Do not suggest System Settings, Privacy & Security, chmod, or sudo.

To diagnose a denial:
  nono why --path <blocked-path> --op read

To grant access:
  Option A: exit and restart with --allow <path> on the nono command.
  Option B: write a profile that extends the active one and adds the path,
           save it under ~/.config/nono/profiles/<name>.json, then start with
           --profile <name>."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'
