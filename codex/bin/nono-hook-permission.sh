#!/bin/bash
# nono-hook-permission.sh - Codex PermissionRequest hook
# Version: 1.1.0
#
# Fires when Codex's permission flow asks the user to approve something
# (shell escalation, managed-network access, write outside workspace).
# We do NOT pre-emptively deny — many of those requests are for paths
# the active nono profile already allows, and blocking them produces
# false negatives (e.g. writing to ~/.config/nono/profiles when that
# path is in the profile's allow list).
#
# Instead we attach a one-line advisory as additionalContext so the
# model knows the real boundary is the OS sandbox: if Codex's approval
# is granted but the kernel still blocks the operation, the
# PostToolUse hook will fire with the precise diagnostic.
#
# Schema reference:
#   https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/permission-request.command.output.schema.json

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

CONTEXT="This session is inside a nono OS sandbox. If Codex approval is granted but the operation still fails with EACCES/EPERM/Operation not permitted, the kernel sandbox blocked it (not Codex). The PostToolUse hook will then surface the exact rule and the two restart options — wait for it rather than re-prompting the user."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "additionalContext": $ctx
  }
}'
