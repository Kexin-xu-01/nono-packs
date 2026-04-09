#!/bin/bash
# nono-hook-bash.sh - PostToolUse hook for Bash commands
# Version: 1.0.0
#
# Checks if a Bash command hit a sandbox permission denial by inspecting
# the tool output for common permission error patterns.

# Only run if we're inside a nono sandbox
if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    exit 0
fi

# Read the hook input from stdin
INPUT=$(cat)

# Check the tool output for permission denial patterns
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result_metadata.exit_code // 0' 2>/dev/null)

# Only trigger if there's a permission error in the output
if ! echo "$OUTPUT" | grep -qi "operation not permitted\|permission denied\|EPERM\|EACCES"; then
    exit 0
fi

# Read capabilities from the cap file
CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

CONTEXT="[NONO SANDBOX - PERMISSION DENIED]

STOP. The command you just ran hit the nono sandbox boundary. This is NOT a macOS TCC issue or a regular permissions problem. This is the nono security sandbox blocking access.

Do not suggest macOS System Settings, Full Disk Access, or chmod as fixes. These will not help.

ALLOWED PATHS (everything else is blocked):
$CAPS
Network: $NET

STEP 1 - DIAGNOSE:
Run nono why to understand exactly why access was denied:

  nono why --path /path/that/failed --op read 2>/dev/null

STEP 2 - TELL THE USER:
Present the user with two options and NOTHING ELSE:

  Option A (quick fix): Exit this session and restart with the path allowed:
    nono run --allow /path/to/needed -- claude

  Option B (persistent fix): Offer to write a nono profile so this access is always available. If the user agrees, run 'nono profile guide' to get the full profile schema, then write a profile JSON to ~/.config/nono/profiles/<name>.json. The user can then start sessions with:
    nono run --profile <name> -- claude

IMPORTANT: Do NOT speculate about file contents. Do NOT suggest macOS privacy settings. Do NOT suggest chmod or sudo. This is a nono sandbox denial.

Always run nono why first and always present both options."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
