#!/bin/bash
# nono-hook.sh - OpenClaw hook for nono sandbox diagnostics
# Version: 1.0.0
#
# Fires on tool failures. Only injects sandbox context when the failure
# looks like an actual sandbox denial.

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)

# Gate: only fire on actual sandbox denial signatures.
if ! echo "$INPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    exit 0
fi

FAILED_PATH=$(echo "$INPUT" | grep -oE '/[^[:space:]"'"'"']+' | head -n 1)
DISPLAY_PATH="${FAILED_PATH:-<blocked-path>}"

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

CONTEXT="Sandbox denial detail:

Run for the precise rule that blocked it:
  nono why --path $DISPLAY_PATH --op read

Present the user with these two options (and nothing else):

  Option A — quick fix (one-off): exit and restart with the path allowed:
    nono run --allow $DISPLAY_PATH -- openclaw

  Option B — persistent fix: save this profile to
  ~/.config/nono/profiles/<chosen-name>.json then start with:
    nono run --profile <chosen-name> -- openclaw

  {
    \"extends\": \"openclaw\",
    \"meta\": { \"name\": \"<chosen-name>\", \"version\": \"1.0.0\" },
    \"filesystem\": { \"read\": [\"$DISPLAY_PATH\"] }
  }
  // change \"openclaw\" to the user's active profile name if
  //   they started from a custom one.
  // use \"read\" for read-only, \"write\" for write-only, or
  //   \"allow\" for r+w access.

Allowed paths in this session:
$CAPS
Network: $NET"

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": $ctx
  }
}'
