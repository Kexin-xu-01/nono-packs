"""Hermes plugin for nono sandbox diagnostics."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any


DENIAL_RE = re.compile(
    r"operation not permitted|permission denied|eperm|eacces|landlock|sandbox.*denied",
    re.IGNORECASE,
)
PATH_RE = re.compile(r"(?:~/|/)[^\s\"'`,;:]+")
_ANNOUNCED: set[str] = set()


def _session_key(args: tuple[Any, ...], kwargs: dict[str, Any]) -> str:
    return str(
        kwargs.get("session_id")
        or kwargs.get("task_id")
        or kwargs.get("conversation_id")
        or "default"
    )


def _cap_file() -> Path | None:
    value = os.environ.get("NONO_CAP_FILE")
    if not value:
        return None
    path = Path(value)
    if not path.is_file():
        return None
    return path


def _inside_nono() -> bool:
    return _cap_file() is not None


def _load_capabilities(limit: int = 24) -> str:
    path = _cap_file()
    if path is None:
        return "nono capability file is not available."

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return f"Could not read nono capabilities from {path}: {exc}"

    fs_entries = data.get("fs", [])
    lines = []
    for entry in fs_entries[:limit]:
        resolved = entry.get("resolved") or entry.get("path") or "<unknown>"
        access = entry.get("access") or "unknown"
        lines.append(f"- {resolved} ({access})")
    if len(fs_entries) > limit:
        lines.append(f"- ... {len(fs_entries) - limit} more entries")

    network = "blocked" if data.get("net_blocked") else "allowed"
    if not lines:
        lines.append("- no filesystem capabilities listed")
    return "Filesystem:\n" + "\n".join(lines) + f"\nNetwork: {network}"


def _stringify(value: Any, max_chars: int = 6000) -> str:
    if isinstance(value, str):
        text = value
    else:
        try:
            text = json.dumps(value, sort_keys=True)
        except Exception:
            text = str(value)
    return text[:max_chars]


def _extract_path(*values: Any) -> str | None:
    for value in values:
        text = _stringify(value)
        match = PATH_RE.search(text)
        if not match:
            continue
        candidate = match.group(0).rstrip(").]")
        if candidate.startswith("~/"):
            return str(Path.home() / candidate[2:])
        if candidate == "~":
            return str(Path.home())
        return candidate
    return None


def _denial_context(path: str | None, capabilities: str) -> str:
    display_path = path or "<blocked-path>"
    why = (
        f"nono why --path {display_path} --op read"
        if path
        else "nono why --path <blocked-path> --op read"
    )
    allow = (
        f"nono run --profile hermes --allow {display_path} -- hermes"
        if path
        else "nono run --profile hermes --allow <blocked-path> -- hermes"
    )

    return f"""[nono sandbox diagnostic]

The previous Hermes tool call appears to have hit the outer nono OS sandbox.
This is not macOS TCC, chmod, sudo, or a Hermes approval issue.

Blocked path: {display_path}

Current nono capabilities:
{capabilities}

Next steps for the assistant:
1. Do not retry the blocked tool call.
2. Run this diagnosis command if the path is concrete:
   {why}
3. Present the user with exactly two remediation choices:
   A. One-off restart:
      {allow}
   B. Persistent profile:
      create or extend ~/.config/nono/profiles/<name>.json with the minimum filesystem grant.
4. Use read/read_file for view-only access and allow/allow_file only when writes are needed.
"""


def _startup_context() -> str:
    return """[nono sandbox context]

This Hermes session is running inside nono. Filesystem and network access are enforced by the operating system before Hermes starts. Hermes approvals, YOLO mode, chmod, sudo, and macOS privacy settings cannot expand nono capabilities from inside the session.

If a tool fails with "Operation not permitted", "Permission denied", EACCES, EPERM, "landlock", or "sandbox denied", diagnose with:
  nono why --path <path> --op read

Then offer either a one-off restart with an explicit nono grant or a persistent profile change under ~/.config/nono/profiles/.
"""


def _nono_status(_params: dict[str, Any] | None = None) -> str:
    status = {
        "inside_nono": _inside_nono(),
        "capability_file": str(_cap_file()) if _cap_file() else None,
        "capabilities": _load_capabilities(),
        "guidance": "Use nono why --path <path> --op <read|write|readwrite> for denied paths.",
    }
    return json.dumps(status, indent=2)


def _augment_tool_result(*args: Any, **kwargs: Any) -> str | None:
    if not _inside_nono():
        return None

    tool_args = kwargs.get("arguments") or kwargs.get("args")
    result = kwargs.get("result")
    if tool_args is None and len(args) > 1:
        tool_args = args[1]
    if result is None and len(args) > 2:
        result = args[2]

    result_text = _stringify(result)
    if not DENIAL_RE.search(result_text):
        return None

    blocked_path = _extract_path(tool_args, result)
    return result_text + "\n\n" + _denial_context(blocked_path, _load_capabilities())


def _inject_context(*args: Any, **kwargs: Any) -> dict[str, str] | None:
    if not _inside_nono():
        return None

    key = _session_key(args, kwargs)
    is_first_turn = bool(kwargs.get("is_first_turn"))
    if not is_first_turn or key in _ANNOUNCED:
        return None

    _ANNOUNCED.add(key)
    return {"context": _startup_context()}


def register(ctx: Any) -> None:
    schema = {
        "name": "nono_status",
        "description": "Show the current nono sandbox capability summary when Hermes is running inside nono.",
        "parameters": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    }

    ctx.register_tool("nono_status", schema, _nono_status)
    ctx.register_hook("transform_tool_result", _augment_tool_result)
    ctx.register_hook("pre_llm_call", _inject_context)
