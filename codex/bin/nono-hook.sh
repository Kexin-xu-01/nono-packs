#!/bin/bash
# nono-hook.sh - Codex PostToolUse hook for nono sandbox diagnostics
# Version: 1.4.0
#
# Behavioural change in 1.4.0: path extraction now also looks at
# tool_input and accepts tilde-prefixed paths (`~/test.txt`), not
# just absolute `/...` forms. Earlier versions silently fell back
# to a `<blocked-path>` literal when the denial only mentioned the
# tilde form, which then surfaced in user-facing output.
#
# Behavioural change in 1.3.0: the additionalContext no longer contains
# any <placeholder> tokens. The hook derives a default profile name
# from the blocked path basename (e.g. /home/u/test.txt → codex-test-txt)
# and substitutes it into the JSON template before emitting. This is a
# response to v1.2.0 behaviour where Codex's model echoed `<chosen-name>`
# back to the user verbatim despite explicit instructions to substitute
# a real name — placeholders are clearly mishandled by the model in
# this position. The hook still asks the model to write the file via
# its file-write tool, but if it falls back to printing the template,
# the printout is now directly usable.
#
# 1.2.0 introduced the "act, don't parrot" framing (kept in 1.3.0).
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

# Path extraction. Try multiple sources in order of fidelity:
#  1. tool_input — the original argument the model passed (e.g. the
#     `path` field for Read, or extracted from `command` for Bash).
#     This carries the user-typed form (`~/test.txt`, `./foo`).
#  2. tool_response — the error string. Catches absolute paths the
#     kernel/OpenSSL/etc surface in their messages.
# Accept both `/` absolute and `~/` tilde-prefixed forms — earlier
# versions only matched `/...` and fell back to a `<blocked-path>`
# literal when the denial reported a tilde path.
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null)
PATH_REGEX='(~/|/)[^[:space:]"'"'"',]+'
FAILED_PATH=$(echo "$TOOL_INPUT" | grep -oE "$PATH_REGEX" | head -n 1)
[ -z "$FAILED_PATH" ] && FAILED_PATH=$(echo "$TOOL_RESPONSE" | grep -oE "$PATH_REGEX" | head -n 1)
# Resolve tilde to $HOME so all downstream uses (the suggested
# command, the `read:` array, the derived profile name) are unambiguous.
case "$FAILED_PATH" in
    "~/"*) FAILED_PATH="${HOME}/${FAILED_PATH#\~/}" ;;
    "~")   FAILED_PATH="$HOME" ;;
esac
DISPLAY_PATH="${FAILED_PATH:-<blocked-path>}"

# Pack identity. Hardcoded — the pack ships with `install_as: codex`,
# so suggesting `extends: "codex"` is correct for any user who
# started from the pack profile directly. The template includes a
# comment for users on a custom intermediate to update by hand.
PACK_PROFILE="codex"

# Derive a default profile name from the blocked path so the
# additionalContext never contains a `<placeholder>` token — earlier
# versions used `<chosen-name>` and Codex's model parroted it back to
# the user verbatim. Pre-substituting a real name means the worst
# case (model just echoes our template) still produces something the
# user can copy-paste. Algorithm: lowercase, basename, kebab-case,
# strip any chars outside [a-z0-9-]. Fallback to `${PACK_PROFILE}-extended`.
PATH_BASENAME=$(basename "$DISPLAY_PATH" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9-' '-' \
  | sed -E 's/-+/-/g; s/^-//; s/-$//')
if [ -z "$PATH_BASENAME" ] || [ "$PATH_BASENAME" = "-" ]; then
    DEFAULT_PROFILE_NAME="${PACK_PROFILE}-extended"
else
    DEFAULT_PROFILE_NAME="${PACK_PROFILE}-${PATH_BASENAME}"
fi

REASON="[nono sandbox] $DISPLAY_PATH was blocked by the OS sandbox — not Codex, not TCC, not Unix permissions. See additional context for diagnosis and the two options."

CONTEXT="Sandbox denial. Path blocked: $DISPLAY_PATH
Profile name to use for the persistent fix below: $DEFAULT_PROFILE_NAME

Offer the user TWO choices (A or B). Wait for their answer.

  A) one-off — exit and restart with this path allowed:
       nono run --allow $DISPLAY_PATH -- codex

  B) persistent — create a profile file using the name above
     ($DEFAULT_PROFILE_NAME).

If user picks A: print that command. Stop.

If user picks B: write the file using your file-write tool to
~/.config/nono/profiles/${DEFAULT_PROFILE_NAME}.json with EXACTLY
these contents (the profile name is already filled in — do NOT
substitute placeholders, just write what is below):
{
  \"extends\": \"$PACK_PROFILE\",
  \"meta\": { \"name\": \"$DEFAULT_PROFILE_NAME\", \"version\": \"1.0.0\" },
  \"filesystem\": { \"read\": [\"$DISPLAY_PATH\"] }
}

After writing, tell the user:
  Created. Restart codex with:
    nono run --profile $DEFAULT_PROFILE_NAME -- codex

Stop after either option. Do not retry the blocked tool call — the
user has to restart for the new profile to take effect.

Notes:
  - Use 'read' for view-only; 'write' for modify-only; 'allow' for r+w.
    Default is 'read' above.
  - For the precise rule that blocked the path: nono why --path $DISPLAY_PATH --op read"

jq -n --arg reason "$REASON" --arg ctx "$CONTEXT" '{
  "decision": "block",
  "reason": $reason,
  "systemMessage": "nono sandbox denial",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
