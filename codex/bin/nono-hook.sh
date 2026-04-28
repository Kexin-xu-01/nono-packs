#!/bin/bash
# nono-hook.sh - Codex PostToolUse hook for nono sandbox diagnostics
# Version: 1.2.0
#
# Behavioural change in 1.2.0: the additionalContext now instructs the
# model to ACT on the user's choice (write the profile file directly
# via its file-write tool when they pick Option B), rather than just
# re-pasting the JSON template with `<chosen-name>` placeholders for
# the user to fill in. Earlier versions left the model parroting the
# template back, which was confusing UX.
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

CONTEXT="Sandbox denial detail. Path blocked: $DISPLAY_PATH

Offer the user TWO choices (A or B). Wait for their answer before doing anything.

  Option A (one-off): they exit and restart with this path allowed:
    nono run --allow $DISPLAY_PATH -- codex

  Option B (persistent): you create a profile file for them.

If they pick A: print the command above and stop. They will exit and restart themselves.

If they pick B: do the following yourself, do NOT just paste the JSON back:
  1. Pick a short descriptive profile name based on what is being granted
     (e.g. for a Documents path use 'codex-docs'; for a single file use
     'codex-with-<basename>'). Use the active pack profile '$PACK_PROFILE'
     as the base for the name. Avoid '<chosen-name>' literally — pick a real name.
  2. Use your file-write tool to create the file at:
       ~/.config/nono/profiles/<that-name>.json
     with these exact contents (substitute the name you picked):
       {
         \"extends\": \"$PACK_PROFILE\",
         \"meta\": { \"name\": \"<that-name>\", \"version\": \"1.0.0\" },
         \"filesystem\": { \"read\": [\"$DISPLAY_PATH\"] }
       }
  3. Tell the user the file has been written and give them the command to
     start the new session:
       nono run --profile <that-name> -- codex
  4. Stop. Do not retry the original tool call — they need to restart codex
     for the new profile to take effect.

Notes for both options:
  - Use 'read' if they only need to view; 'write' if only modify;
    'allow' for read+write.
  - If the user started from a custom profile (not '$PACK_PROFILE'
    directly), substitute that name in 'extends' instead.
  - For diagnosing the exact rule that blocked the path, the user can run:
      nono why --path $DISPLAY_PATH --op read"

jq -n --arg reason "$REASON" --arg ctx "$CONTEXT" '{
  "decision": "block",
  "reason": $reason,
  "systemMessage": "nono sandbox denial",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
