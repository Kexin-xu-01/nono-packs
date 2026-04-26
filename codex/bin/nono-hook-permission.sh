#!/bin/bash
# nono-hook-permission.sh - Codex PermissionRequest hook
# Version: 1.0.0
#
# Fires when Codex's permission flow asks the user to approve something
# (shell escalation, managed-network access). Inside a nono session,
# Codex's approval doesn't actually grant the access — the OS sandbox
# does. So we deny upstream and tell the user to restart nono with the
# right grant rather than wait for an answer Codex's flow can't honour.
#
# Schema reference:
#   https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/permission-request.command.output.schema.json

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)

# bypassPermissions is the user's explicit yolo opt-in — leave Codex's
# flow alone in that case.
PMODE=$(echo "$INPUT" | jq -r '.permission_mode // "default"' 2>/dev/null)
if [ "$PMODE" = "bypassPermissions" ]; then
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null)

MESSAGE="Approval cannot grant access here — the outer nono sandbox enforces capabilities at the OS level. To proceed, exit Codex and restart nono with the path or domain explicitly allowed:
  nono run --allow <path> -- codex
or use --allow-net for network access. See \`nono why\` for what's currently granted."

if [ -n "$DESCRIPTION" ]; then
    MESSAGE+="

Codex requested: $DESCRIPTION"
fi

if [ -n "$TOOL_NAME" ]; then
    MESSAGE+="
Tool: $TOOL_NAME"
fi

jq -n --arg msg "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": $msg
    }
  }
}'
