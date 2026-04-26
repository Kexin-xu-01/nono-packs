#!/bin/bash
# nono-hook.sh - Codex PostToolUse hook for nono sandbox diagnostics
# Version: 1.0.0
#
# Fires after every Bash / apply_patch invocation. When the tool_response
# matches a sandbox-denial signature, returns a JSON block with both a
# user-facing `reason` and an agent-facing `additionalContext` so the
# user sees the boundary message verbatim and the agent has the full
# diagnostic available for follow-up turns.
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

# Be silent in bypassPermissions mode — the user has explicitly opted
# into yolo and probably doesn't want a wall of guidance per denial.
PMODE=$(echo "$INPUT" | jq -r '.permission_mode // "default"' 2>/dev/null)
if [ "$PMODE" = "bypassPermissions" ]; then
    exit 0
fi

# tool_response is `true` (any) in the schema — coerce to a string for
# greppability, regardless of whether it's a JSON object or scalar.
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response | tostring' 2>/dev/null)
if ! echo "$TOOL_RESPONSE" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|landlock|sandbox.*denied'; then
    exit 0
fi

# Best-effort: pull the first absolute path mentioned in the response.
FAILED_PATH=$(echo "$TOOL_RESPONSE" | grep -oE '/[^[:space:]"'"'"']+' | head -n 1)

# Pack identity. Hardcoded — the pack ships with `install_as: codex`,
# so suggesting `extends: "codex"` is correct for any user who started
# from the pack profile directly. The template includes a comment for
# users on a custom intermediate to update by hand.
PACK_PROFILE="codex"

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

REASON="[NONO SANDBOX - PERMISSION DENIED]

This is a nono sandbox boundary, not a Codex permission, not macOS TCC,
not a Unix permissions issue. Codex's own approval flow cannot bypass it.

Allowed paths:
$CAPS
Network: $NET
"

if [ -n "$FAILED_PATH" ]; then
    REASON+="
Blocked path: $FAILED_PATH
"
fi

REASON+="
Two options for the user:

  Option A (quick fix): exit and restart with the path allowed:
    nono run --allow ${FAILED_PATH:-/path/to/needed} -- codex

  Option B (persistent fix): save this profile to
  ~/.config/nono/profiles/<chosen-name>.json, then start with:
    nono run --profile <chosen-name> -- codex

  {
    \"extends\": \"$PACK_PROFILE\",
    \"meta\": { \"name\": \"<chosen-name>\", \"version\": \"1.0.0\" },
    \"filesystem\": { \"read\": [\"${FAILED_PATH:-/path/to/needed}\"] }
  }
  // ↑ change \"$PACK_PROFILE\" to your active profile if you started
  //   from a custom one. Use \"read\" for read-only, \"write\" for
  //   write-only, or \"allow\" for r+w access.

For detailed diagnosis:
  nono why --path ${FAILED_PATH:-<blocked-path>} --op read"

jq -n --arg reason "$REASON" '{
  "decision": "block",
  "reason": $reason,
  "systemMessage": "nono sandbox denial — see reason for diagnosis and options",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $reason
  }
}'
