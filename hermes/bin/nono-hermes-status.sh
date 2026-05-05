#!/usr/bin/env bash
set -eu

echo "Hermes:"
if command -v hermes >/dev/null 2>&1; then
  hermes --version || true
else
  echo "  hermes: not found on PATH"
fi

echo
echo "nono:"
if command -v nono >/dev/null 2>&1; then
  nono --version || true
else
  echo "  nono: not found on PATH"
fi

echo
echo "nono sandbox:"
if [ -n "${NONO_CAP_FILE:-}" ] && [ -f "$NONO_CAP_FILE" ]; then
  echo "  capability file: $NONO_CAP_FILE"
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      "  network: " + (if .net_blocked then "blocked" else "allowed" end),
      "  filesystem:",
      (.fs[]? | "    " + ((.resolved // .path) | tostring) + " (" + (.access | tostring) + ")")
    ' "$NONO_CAP_FILE"
  else
    echo "  jq not found; raw capability file:"
    sed -n '1,80p' "$NONO_CAP_FILE"
  fi
else
  echo "  not running inside a nono session, or NONO_CAP_FILE is unavailable"
fi

echo
echo "Hermes security files:"
for path in "$HOME/.hermes/.env" "$HOME/.hermes/config.yaml"; do
  if [ -e "$path" ]; then
    perms=$(stat -f "%Lp" "$path" 2>/dev/null || stat -c "%a" "$path" 2>/dev/null || echo "unknown")
    echo "  $path permissions: $perms"
  else
    echo "  $path: missing"
  fi
done
