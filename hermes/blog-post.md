# Running Hermes Agent Safely with nono: A Deep Dive into the Hermes Pack

Hermes Agent from Nous Research is a powerful, locally-run AI agent that can execute code, browse the web, read files, and call external APIs on your behalf. That power is exactly why it needs guardrails. The `always-further/hermes` nono pack wraps Hermes in a security sandbox that enforces OS-level access controls, intercepts credential traffic, and gives the agent — and you — clear visibility into what is and isn't permitted.

This post covers how the pack works, why each piece exists, and how to configure it for your setup.

---

## What the Pack Installs

The pack ships three layers:

1. **A nono security profile** (`policy.json`) — defines the sandbox boundary: which filesystem paths Hermes can reach, which provider APIs it can call, and the credential routes it can use.
2. **A Hermes plugin** (`plugin/nono-sandbox`) — a Python plugin that Hermes loads at startup. It adds the `nono_status` tool, the `/nono-status` command, and lifecycle hooks that catch sandbox denials and explain them to the agent.
3. **A bundled skill** (`SKILL.md`) — Markdown that Hermes loads as a skill so the agent knows how to diagnose and remediate sandbox failures without you having to prompt it.

Install with a single command:

```bash
nono run --profile always-further/hermes -- hermes
```

nono pulls the pack on first use, symlinks the plugin into `~/.hermes/plugins/nono-sandbox`, and merges the config-hardening template into `~/.hermes/config.yaml`.

---

## The Security Profile

The base profile (`policy.json`) extends nono's `default` policy and adds Hermes-specific permissions.

### Filesystem access

Hermes needs to read and write its own state directory, and it needs read access to the Python runtimes that uv manages:

```json
"filesystem": {
  "allow": [
    "$HOME/.hermes",
    "$HOME/.config/nono/profile-drafts"
  ],
  "read": [
    "$HOME/.local/bin",
    "$HOME/.local/share/uv",
    "$HOME/.config/nono/packages"
  ]
}
```

`$HOME/.hermes` gets full read/write because Hermes stores sessions, skills, logs, pairing files, and its `.env` there. The profile-drafts directory is writable so Hermes can suggest new profile configurations — but active profiles under `~/.config/nono/profiles` are read-only from inside the sandbox. Policy changes always require a user promotion step outside the session.

### Isolation mode

```json
"security": {
  "signal_mode": "isolated",
  "capability_elevation": false
}
```

`signal_mode: isolated` means the sandboxed process cannot send signals to processes outside its group. `capability_elevation: false` prevents any `setuid`, `setcap`, or privilege escalation calls. From inside a Hermes session, `sudo`, `chmod`, and macOS Full Disk Access prompts have no effect on nono's enforcement — the OS-level Landlock (Linux) or Seatbelt (macOS) rules were already in place before Hermes started.

### Config hardening

When the pack is pulled, nono merges `templates/config-hardening.yaml` into `~/.hermes/config.yaml`:

```yaml
approvals:
  mode: manual
  timeout: 60

security:
  redact_secrets: true
  tirith_enabled: true
  tirith_fail_open: false
  allow_private_urls: false
  website_blocklist:
    enabled: true
    domains:
      - "*.internal"
      - "*.local"
      - "metadata.google.internal"
      - "metadata.goog"

skills:
  guard_agent_created: true
```

This locks Hermes' own approval system to manual mode, enables secret redaction in logs, turns on Tirith (Hermes' policy engine) in fail-closed mode, blocks access to cloud metadata endpoints, and prevents the agent from creating skills without review. These are Hermes-level controls that operate in addition to the nono sandbox — not instead of it.

---

## Credential Injection

The most interesting part of the pack is how credentials reach the agent without ever being placed in environment variables that Hermes or any subprocess could read directly.

### The phantom token approach

When a credential route is enabled, nono generates a **session-scoped phantom token** — a short-lived, random string that has no value outside the current nono session. This token is injected into the process environment (e.g. `OPENAI_API_KEY=<phantom>`). Hermes and its SDKs pick it up and use it as they would a real key.

Traffic leaves the process, hits nono's local proxy, and the proxy:

1. Verifies the phantom token via `NONO_PROXY_TOKEN` (also in the environment, but redacted in status output).
2. Looks up the real credential from the system keychain.
3. Swaps the phantom token for the real key in the appropriate request header.
4. Enforces the endpoint allowlist before forwarding.

Your real API key never touches Hermes' memory or disk. A compromised Hermes session cannot exfiltrate the credential — the phantom token is meaningless outside the proxy.

### Provider routes

The pack defines five provider routes in `policy.json`:

| Route | Upstream | Credential header |
|---|---|---|
| `openai` | `https://api.openai.com/v1` | `Authorization: Bearer {}` |
| `anthropic` | `https://api.anthropic.com` | `x-api-key: {}` |
| `gemini` | `https://generativelanguage.googleapis.com` | `x-goog-api-key: {}` |
| `github` | `https://api.github.com` | `Authorization: token {}` |
| `gitlab` | `https://gitlab.com/api` | `Authorization: Bearer {}` |

The OpenAI, Anthropic, and Gemini routes include **method + path allowlists**. For example, the Anthropic route only permits:

```json
{ "method": "POST", "path": "/v1/messages" },
{ "method": "POST", "path": "/v1/messages/**" },
{ "method": "POST", "path": "/v1/complete" },
{ "method": "GET", "path": "/v1/models" },
{ "method": "GET", "path": "/v1/models/**" }
```

Even if an attacker were to control Hermes' tool calls and point the SDK at the Anthropic proxy, they could not use the credential to call arbitrary endpoints — only the routes in the allowlist go through.

### None enabled by default

The base profile ships with `"credentials": []`. This is deliberate: if a route is not enabled, the proxy never intercepts that traffic, and the phantom token is never generated for it. A session that only needs Gemini doesn't have an `OPENAI_API_KEY` in its environment at all, even as a phantom — so there's no surface to attack.

### Enabling credentials in an extending profile

Create a child profile that extends `hermes` and list only the routes you need:

```bash
nono pull always-further/hermes
nono profile init hermes-agent --extends hermes --full --force \
  --output ~/.config/nono/profile-drafts/hermes-agent.json
```

Edit the draft and set the `credentials` array:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["gemini", "github"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {}
}
```

The `custom_credentials` block in the child profile can stay empty — route definitions are inherited from the parent. Do not copy the full `custom_credentials` block from the base profile into your child unless you intend to override the route templates. Child entries override inherited ones, so a partial copy can silently break the route.

Validate and promote the draft:

```bash
nono profile validate --draft hermes-agent
nono profile promote hermes-agent
```

Then launch Hermes with the child profile:

```bash
nono run --profile hermes-agent -- hermes
```

### Storing credentials

nono reads credentials from the system keychain using env-var-shaped account names:

**macOS Keychain:**

```bash
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w
security add-generic-password -U -s "nono" -a "GITHUB_TOKEN" -w
```

The `-w` flag at the end prompts for the secret interactively, so the value never appears in shell history.

**Linux Secret Service:**

```bash
secret-tool store --label="nono: GOOGLE_API_KEY" \
  service nono username GOOGLE_API_KEY target default

secret-tool store --label="nono: GITHUB_TOKEN" \
  service nono username GITHUB_TOKEN target default
```

For 1Password, Apple Passwords, file-backed secrets, or environment references, use nono credential URI refs in your profile's `custom_credentials`:

```json
"custom_credentials": {
  "openai": {
    "credential_ref": "op://Personal/OpenAI/credential"
  }
}
```

nono supports `op://`, `apple-password://`, `file:///`, `env://`, and `keyring://` refs.

---

## The nono-sandbox Plugin

The plugin (`plugin/nono-sandbox/__init__.py`) has four responsibilities:

### 1. Startup context injection

On the first LLM turn of a session, the plugin injects a brief system context block:

```
[nono sandbox context]

This Hermes session is running inside nono. Filesystem and network access
are enforced by the operating system before Hermes starts. Hermes approvals,
YOLO mode, chmod, sudo, and macOS privacy settings cannot expand nono
capabilities from inside the session.
```

This prevents a common failure mode where the agent tries to resolve a permission denial by suggesting `sudo` or macOS privacy prompts — both of which are invisible to nono's enforcement layer.

### 2. Tool result augmentation

The `transform_tool_result` hook scans every tool result for denial patterns (`operation not permitted`, `permission denied`, `EACCES`, `EPERM`, `landlock`, `sandbox denied`). When it finds a match, it appends a structured diagnostic block:

```
[nono sandbox diagnostic]

The previous Hermes tool call appears to have hit the outer nono OS sandbox.
This is not macOS TCC, chmod, sudo, or a Hermes approval issue.

Blocked path: /some/blocked/path

Current nono capabilities:
Filesystem:
- /home/user/.hermes (readwrite)
- /home/user/.local/bin (read)
...
Network: allowed

Next steps for the assistant:
1. Do not retry the blocked tool call.
2. Run this diagnosis command if the path is concrete:
   nono why --self --path /some/blocked/path --op read
3. Present the user with exactly two remediation choices:
   A. One-off restart: nono run --profile hermes --allow /some/blocked/path -- hermes
   B. Persistent profile: create or extend ~/.config/nono/profile-drafts/<name>.json
```

The agent sees the denial and the remediation path in the same context window as the failure, without requiring you to intervene.

### 3. The `nono_status` tool

The plugin registers a `nono_status` tool that Hermes can call at any point:

```python
def _nono_status(_params=None, **_kwargs):
    return json.dumps({
        "inside_nono": _inside_nono(),
        "capability_file": str(_cap_file()) if _cap_file() else None,
        "capabilities": _load_capabilities(),
        "proxy": _proxy_status(),
        "guidance": "Use nono why --self --path <path> --op <read|write|readwrite> ..."
    }, indent=2)
```

Proxy status output redacts credentials: `NONO_PROXY_TOKEN` is reported as `"set"`, and proxy URLs have credentials replaced with `<redacted>`.

### 4. The `/nono-status` command

For interactive use, `nono-hermes-status.sh` prints Hermes and nono versions, the live capability file, proxy and TLS environment variables, and filesystem permissions on `~/.hermes/.env` and `~/.hermes/config.yaml`. This is useful for diagnosing setup issues before starting a session.

---

## The nono-sandbox Skill

The bundled skill (`SKILL.md`) is loaded by the plugin at startup as `nono-sandbox:nono-sandbox`. When Hermes encounters a denial, it can retrieve the skill and follow its structured remediation protocol:

- Identify the blocked path from stderr, tracebacks, or command arguments.
- Run `nono why --self --path <path> --op <read|write|readwrite>`.
- Present exactly two options: one-off restart or persistent profile draft.
- Never suggest Full Disk Access, `chmod`, `sudo`, or Hermes approval for a nono denial.
- Never retry a blocked tool through a different path.
- Never write directly to `~/.config/nono/profiles` from inside the sandbox.

The skill ships from a signed nono pack, so its provenance is verifiable. Load it explicitly as `skill_view("nono-sandbox:nono-sandbox")` when that matters.

---

## The Bigger Picture

The design philosophy here is **minimum-surface, deny-by-default, user-reviewed escalation**:

- The sandbox enforces limits at the OS level before Hermes starts. Nothing that runs inside the session can bypass them.
- Credentials are never placed in plaintext environment variables. The proxy holds the real keys; the session holds phantoms.
- Unused credential routes are not in scope. If you don't need OpenAI, `OPENAI_API_KEY` doesn't exist in the environment — even as a phantom.
- Endpoint allowlists cap what credentialed routes can actually reach. Even if a credential were somehow exfiltrated, it could only reach the specific API paths in the allowlist.
- Policy changes require an explicit user promotion step outside the session. The agent can draft profiles; only you can activate them.
- The agent gets structured, actionable information when something is blocked, rather than an opaque error that leads to retry loops.

This makes it practical to run an agent with real API credentials on a developer machine without worrying that a prompt injection, a buggy tool call, or an unexpected code path can reach credentials or files it shouldn't.

---

## Quick Reference

```bash
# Install and run with the base profile (no credentials)
nono run --profile always-further/hermes -- hermes

# Create an extending profile with specific credentials
nono pull always-further/hermes
nono profile init hermes-agent --extends hermes --full --force \
  --output ~/.config/nono/profile-drafts/hermes-agent.json

# Edit the draft, then validate and promote
nono profile validate --draft hermes-agent
nono profile promote hermes-agent

# Run with the child profile
nono run --profile hermes-agent -- hermes

# Store a credential (macOS)
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w

# Diagnose a sandbox denial (from inside the session)
nono why --self --path /blocked/path --op read

# Check sandbox status (from inside the session)
nono_status
```

---

The `always-further/hermes` pack is open source and available on the nono registry. If you run Hermes in any context where it touches real credentials or sensitive files, sandboxing it under nono is the practical way to keep the blast radius small.
