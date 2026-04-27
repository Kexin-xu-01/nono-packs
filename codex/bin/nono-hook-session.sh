#!/bin/bash
# nono-hook-session.sh - Codex SessionStart hook
# Version: 1.1.0
#
# Brief boundary statement at session start. Deliberately does NOT
# enumerate allowed paths — that lives in `nono why <path>` and on
# hook fire, not in every session header. Earlier versions emitted
# the full allow list which crowded the conversation with noise.
#
# Schema reference:
#   https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/session-start.command.output.schema.json

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

CONTEXT="You are running inside a nono security sandbox (Landlock on Linux, Seatbelt on macOS). Filesystem and network access is OS-enforced — there is no way to escape from inside this session.

When a tool call fails with \"Operation not permitted\", \"Permission denied\", EACCES, EPERM, or \"landlock\": the cause is this sandbox, NOT macOS TCC, NOT Unix file permissions, NOT a Codex approval. Do not suggest System Settings, chmod, or sudo. The PostToolUse hook will inject the diagnostic and the user's two options whenever this happens — wait for it rather than guessing."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'
