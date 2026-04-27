#!/bin/bash
# nono-hook.sh - Codex PostToolUse hook for nono sandbox diagnostics
# Version: 1.1.0
#
# Splits user-visible from agent-visible content so the conversation
# stays readable:
#   `reason`            = ONE-LINE user-visible block reason.
#   `additionalContext` = full diagnostic + Option A/B template, only
#                         visible to the agent on follow-up turns.
#
# Earlier versions emitted the same wall-of-text in both fields and
# duplicated the allow-list dump that SessionStart already provides.
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

# Pack identity. Hardcoded — the pack ships with `install_as: codex`,
# so suggesting `extends: "codex"` is correct for any user who
# started from the pack profile directly. The template includes a
# comment for users on a custom intermediate to update by hand.
PACK_PROFILE="codex"

REASON="[nono sandbox] $DISPLAY_PATH was blocked by the OS sandbox — not Codex, not TCC, not Unix permissions. See additional context for diagnosis and the two options."

CONTEXT="Sandbox denial detail:

Run for the precise rule that blocked it:
  nono why --path $DISPLAY_PATH --op read

Present the user with these two options (and nothing else):

  Option A — quick fix (one-off): exit and restart with the path allowed:
    nono run --allow $DISPLAY_PATH -- codex

  Option B — persistent fix: save this profile to
  ~/.config/nono/profiles/<chosen-name>.json then start with:
    nono run --profile <chosen-name> -- codex

  {
    \"extends\": \"$PACK_PROFILE\",
    \"meta\": { \"name\": \"<chosen-name>\", \"version\": \"1.0.0\" },
    \"filesystem\": { \"read\": [\"$DISPLAY_PATH\"] }
  }
  // change \"$PACK_PROFILE\" to the user's active profile name if
  //   they started from a custom one.
  // use \"read\" for read-only, \"write\" for write-only, or
  //   \"allow\" for r+w access."

jq -n --arg reason "$REASON" --arg ctx "$CONTEXT" '{
  "decision": "block",
  "reason": $reason,
  "systemMessage": "nono sandbox denial",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
