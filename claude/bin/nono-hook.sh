#!/bin/bash
# nono-hook.sh - Claude Code plugin hook for nono sandbox diagnostics
# Version: 1.1.0
#
# This hook fires on PostToolUseFailure and injects sandbox capability
# information so Claude understands what went wrong and how to fix it.

# Only run if we're inside a nono sandbox
if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi

# Check if jq is available (required for JSON parsing)
if ! command -v jq &> /dev/null; then
    exit 0
fi

# Read capabilities from the cap file
CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

# Build context message with clear, actionable instructions
CONTEXT="[NONO SANDBOX - PERMISSION DENIED]

STOP. Do not try alternative approaches. This is a hard security boundary.

You are running inside the nono security sandbox. The operation you just attempted is PERMANENTLY BLOCKED for this session. There is NO workaround possible from inside this session.

ALLOWED PATHS (everything else is blocked):
$CAPS
Network: $NET

FORBIDDEN ACTIONS - DO NOT ATTEMPT:
- Trying alternative file paths
- Copying files to allowed locations
- Using sudo or changing permissions
- Suggesting the user run commands manually
- Any other workaround

STEP 1 - DIAGNOSE:
Run nono why to understand exactly why access was denied:

  nono why --path /path/that/failed --op read 2>/dev/null

This will tell you the reason, which rule blocked it, and a suggested fix.

STEP 2 - TELL THE USER:
Present the user with two options and NOTHING ELSE:

  Option A (quick fix): Exit this session and restart with the path allowed:
    nono run --allow /path/to/needed -- claude

  Option B (persistent fix): Offer to write a nono profile so this access is always available. If the user agrees, run 'nono profile guide' to get the full profile schema, then write a profile JSON to ~/.config/nono/profiles/<name>.json. The user can then start sessions with:
    nono run --profile <name> -- claude

IMPORTANT: Do NOT speculate about the contents of blocked files. Do NOT provide example file formats, templates, or guesses about what the blocked file contains. You cannot read it. Only present the two options above and ask the user which they prefer.

Always run nono why first and always present both options."

# Output JSON for Claude Code hook system
jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": $ctx
  }
}'
