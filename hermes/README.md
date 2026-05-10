# nono hermes

Sandbox profile, Hermes plugin, and Hermes skill for running [Hermes Agent](https://hermes-agent.nousresearch.com/) inside a [nono](https://nono.sh) security sandbox.

Install:

```bash
nono run --profile hermes -- hermes
```

If the pack is not already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** — sandbox profile loaded as `--profile hermes`. Grants Hermes state under `~/.hermes`, nono user profile writes under `~/.config/nono/profiles`, read-only package metadata under `~/.config/nono/packages`, the Hermes launcher directory, and uv-managed Python runtimes under `~/.local/share/uv`. It does not grant access to nono's own audit or rollback state.
- **`policy.json` network controls** — activates the nono `enterprise` network profile, provider credential routes, and L7 endpoint rules for OpenAI, Anthropic, and Gemini routes. Requires nono v0.51+ so those controls also apply to TLS CONNECT traffic through nono's interception path.
- **`plugin/nono-sandbox/`** — Hermes plugin. It registers a `nono_status` tool, `/nono-status` slash command, plugin-provenanced `nono-sandbox:nono-sandbox` skill, first-turn sandbox boundary context, redacted proxy/TLS trust context, denial remediation context, and metadata-only audit events under `~/.hermes/logs/nono-sandbox-audit.ndjson`.
- **`bin/nono-hermes-status.sh`** — small diagnostic script for checking Hermes, nono, current capabilities, proxy/TLS trust state, and sensitive Hermes file permissions.
- **`templates/config-hardening.yaml`** — YAML merge patch for enabling the plugin, fail-closed Tirith scanning, secret redaction, private URL blocking, and Hermes skill-write guarding.

## Activating the plugin

`nono pull always-further/hermes` symlinks the plugin into:

```text
~/.hermes/plugins/nono-sandbox
```

and merges this into `~/.hermes/config.yaml`:

```yaml
plugins:
  enabled:
    - nono-sandbox
```

Hermes loads the skill through the plugin, preserving its package provenance:

```text
skill_view("nono-sandbox:nono-sandbox")
```

The plugin also exposes `/nono-status` and the `nono_status` tool after Hermes reloads.

## Credential and network filtering

The `hermes` nono profile starts Hermes behind nono's proxy-only network mode unless you override it with `--allow-net`. The profile allows the `enterprise` network set and requests credential routes for `openai`, `anthropic`, `gemini`, `github`, and `gitlab`.

For provider routes, nono injects a session-scoped phantom token into Hermes and swaps it for the real credential in the proxy. The profile uses these nono credential account names:

- `openai_api_key` -> `OPENAI_API_KEY`
- `anthropic_api_key` -> `ANTHROPIC_API_KEY`
- `gemini_api_key` -> `GEMINI_API_KEY`
- built-in `github` and `gitlab` routes when their backing credentials are available

The OpenAI, Anthropic, and Gemini routes include method+path allowlists so model calls can proceed without opening arbitrary API endpoints.

With nono v0.51 or newer, those routes also cover normal HTTPS SDK traffic that uses `CONNECT` through the nono proxy. When a route has credentials or endpoint rules, nono creates a session-scoped interception CA under `~/.nono/sessions/...`, injects the relevant trust environment variables (`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, `CURL_CA_BUNDLE`, and `GIT_SSL_CAINFO`), terminates the eligible TLS tunnel, and applies the same L7 filtering and credential injection inside the proxy. If TLS interception cannot be prepared, nono blocks L7-bearing CONNECT routes instead of allowing a bypass.

The status helper redacts proxy URL userinfo because v0.51 proxy URLs can contain the session proxy token.

## Research notes

The pack maps directly to Hermes security features:

- Hermes approvals catch risky commands, but nono remains the outer OS boundary. The plugin therefore steers the agent toward `nono why` and profile changes instead of approval workarounds.
- Hermes plugin-bundled skills preserve provenance and avoid copying registry-managed content into the mutable user skill tree.
- Hermes plugin hooks are the right CLI+gateway surface for sandbox diagnostics and metadata-only audit. Gateway-only event hooks are useful for production monitoring, but this pack keeps them out of the default install to avoid surprise network callbacks.
- Hermes supports online skills registries, direct URL installs, GitHub taps, and well-known skill endpoints. `registry.nono.sh` could be valuable as a curated nono-specific skill and pack registry if it keeps signed provenance, review metadata, and security-scan results rather than becoming an unreviewed skill dump.

## Source

`https://github.com/always-further/nono-packs/tree/main/hermes`

Published via Sigstore-signed releases triggered by tags matching `hermes-v*`.
