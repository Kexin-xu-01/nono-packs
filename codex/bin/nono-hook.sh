#!/bin/bash
# nono-hook.sh - Codex PostToolUse hook for nono sandbox diagnostics
# Version: 2.0.0
#
# Fires only on actual sandbox-denial signatures. Emits a single
# short `reason` so the hook output stays compact in the TUI.
# The model reads `reason` and synthesises the next-action steps
# (allow flag vs profile fragment) for the user — the long
# template that earlier versions emitted as `additionalContext`
# blew up the screen on every denial without buying anything the
# model couldn't write itself.
#
# Schema reference:
#   https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/post-tool-use.command.output.schema.json

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)

# Silent in bypassPermissions mode — user has explicitly opted out
# of sandbox-aware nudges.
PMODE=$(echo "$INPUT" | jq -r '.permission_mode // "default"' 2>/dev/null)
[ "$PMODE" = "bypassPermissions" ] && exit 0

# Gate on actual sandbox-denial signatures only. Anything else (file
# too large, file not found, parse errors) is not a sandbox issue.
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response | tostring' 2>/dev/null)
if ! echo "$TOOL_RESPONSE" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|landlock|sandbox.*denied'; then
    exit 0
fi

FAILED_PATH=$(echo "$TOOL_RESPONSE" | grep -oE '/[^[:space:]"'"'"']+' | head -n 1)
DISPLAY_PATH="${FAILED_PATH:-<blocked-path>}"

REASON="[nono] $DISPLAY_PATH blocked by OS sandbox. Tell user: (A) re-run with 'nono run --allow $DISPLAY_PATH -- codex' for one-off, OR (B) save profile extending 'codex' under ~/.config/nono/profiles/<name>.json with filesystem.read=[\"$DISPLAY_PATH\"] then 'nono run --profile <name> -- codex'."

jq -n --arg reason "$REASON" '{
  "decision": "block",
  "reason": $reason,
  "systemMessage": "nono sandbox denial"
}'
