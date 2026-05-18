<p align="center">
  <img src="./assets/logo.png" alt="nono codex" width="500" />
</p>


Sandbox profile, Hermes plugin, and Hermes skill for running [Hermes Agent](https://hermes-agent.nousresearch.com/) inside a [nono](https://nono.sh) security sandbox.

Install:

```bash
  nono run --profile always-further/hermes -- hermes
```

If the pack is not already installed, nono will prompt to pull it.

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



Inside a running Hermes sandbox, use `nono why --self` so the query uses the live capability file.

## Credential and network filtering

The base `hermes` profile does not enable provider credentials by default. This avoids warnings for unused providers and prevents unused credential routes from becoming part of the session boundary.

Create your own profile that extends `hermes`:

```bash
nono pull always-further/hermes
nono profile init hermes-agent --extends hermes --full --force \
  --output ~/.config/nono/profile-drafts/hermes-agent.json
$EDITOR ~/.config/nono/profile-drafts/hermes-agent.json
```

Then set only the credential routes you need:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["gemini"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {}
}
```

The empty `custom_credentials` object in the child profile is fine: child profiles inherit the route definitions from `hermes`. Do not remove `custom_credentials` from the base pack profile if you rely on its route definitions.

Replace the generated `network` block as a whole, especially if the child profile was created from an older Hermes pack. Do not keep stale entries such as `network_profile: "enterprise"`, `credentials: ["openai", "anthropic", "gemini", "github", "gitlab"]`, or a child `custom_credentials.gemini` block. Child `custom_credentials` entries override the inherited route templates.

If you see a warning like `Credential 'GEMINI_API_KEY' not found for route 'gemini'`, your active child profile is not using the current Hermes route template. The Gemini route in this pack uses `GOOGLE_API_KEY`.

Validate and promote the draft yourself:

```bash
nono profile validate --draft hermes-agent
nono profile promote hermes-agent
```

The sandboxed agent can draft profile changes, but it cannot directly edit active profiles under `~/.config/nono/profiles`. This keeps policy changes behind an explicit user promotion step.

Common route names:

```json
"credentials": ["gemini"]
"credentials": ["anthropic"]
"credentials": ["openai"]
"credentials": ["gemini", "github"]
```

For provider routes, nono injects a session-scoped phantom token into Hermes and swaps it for the real credential in the proxy. The profile uses env-var-shaped nono keychain account names:

- `OPENAI_API_KEY` -> `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY` -> `ANTHROPIC_API_KEY`
- `GOOGLE_API_KEY` -> `GOOGLE_API_KEY` for Gemini. Hermes' native Gemini documentation uses this as the primary environment variable, and Hermes also accepts `GEMINI_API_KEY` as an alias.
- `GITHUB_TOKEN` -> `GITHUB_TOKEN`
- `GITLAB_TOKEN` -> `GITLAB_TOKEN`

The OpenAI, Anthropic, and Gemini routes include method+path allowlists so model calls can proceed without opening arbitrary API endpoints.

Store keys under nono's keychain service with the same account names.

macOS Keychain:

```bash
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w
security add-generic-password -U -s "nono" -a "GITHUB_TOKEN" -w
```

Keep `-w` last so macOS prompts for the secret instead of recording it in shell history.

Linux Secret Service:

```bash
# Debian/Ubuntu
sudo apt install libsecret-tools gnome-keyring

# Fedora
sudo dnf install libsecret gnome-keyring

# Arch
sudo pacman -S libsecret gnome-keyring

secret-tool store --label="nono: GOOGLE_API_KEY" \
  service nono username GOOGLE_API_KEY target default

secret-tool store --label="nono: GITHUB_TOKEN" \
  service nono username GITHUB_TOKEN target default
```

On Linux this requires a running Secret Service provider such as GNOME Keyring or KWallet. In SSH-only or headless environments, check the nono credential docs before choosing a storage backend.

For 1Password, Apple Passwords, file-backed secrets, environment references, or a non-default keyring service, use nono credential URI refs in your extending profile's `custom_credentials` entries. nono supports refs such as `op://vault/item/field`, `apple-password://server/account`, `file:///absolute/path`, `env://VAR_NAME`, and `keyring://service/account`. See the nono docs for the full credential model:

- https://docs.nono.sh/usage/secrets
- https://docs.nono.sh/usage/flags

Run Hermes with the child profile:

```bash
nono run --profile hermes-agent -- hermes
```

## Complaints about __pycache__

`PYTHONDONTWRITEBYTECODE=1` prevents Python from trying to create `__pycache__` under the signed, read-only package store while Hermes imports the plugin. Do not grant write access to `~/.config/nono/packages/.../plugin/nono-sandbox` to silence that cache write.

When checking capabilities from outside Hermes, include the profile context:

```bash
nono why --profile hermes --path ~/.config/nono/packages/<ns>/hermes/plugin/nono-sandbox/__init__.py --op read
```