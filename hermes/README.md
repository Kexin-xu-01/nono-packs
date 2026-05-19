<p align="center">
  <img src="./assets/logo.png" alt="nono codex" width="500" />
</p>


AI agents are powerful - and that's the problem. An agent with access to your shell, your files, and your API keys is also a target. A malicious prompt, a compromised tool, or a supply-chain attack in a dependency can turn Hermes against you: exfiltrating source code, leaking credentials, or making API calls you never authorised.

This plugin runs [Hermes Agent](https://hermes-agent.nousresearch.com/) inside a [nono](https://nono.sh) security sandbox to limit the damage if something goes wrong:

- **Your API keys stay out of the process.** nono uses a phantom credential model — Hermes never sees your real keys. The proxy swaps in the real credential only at the network boundary, so a compromised agent or tool cannot steal and reuse them elsewhere.
- **File access is locked to what you allow.** The OS kernel (Landlock on Linux, Seatbelt on macOS) enforces which paths Hermes can read or write. It cannot reach your SSH keys, dotfiles, or anything outside the declared scope — regardless of what it's instructed to do.
- **Credential misuse is blocked at the API level.** Even when Hermes has network access, each credential route can be locked to a specific set of API endpoints. A phantom token for your OpenAI key can be restricted to `/v1/chat/completions` only — so a compromised agent cannot use it to query billing, enumerate your organisation, or hit any other API surface you haven't explicitly permitted.
- **Every session is audited.** nono writes a tamper-evident, append-only log of everything Hermes did — commands, capability decisions, network events, and filesystem paths — so you can review exactly what happened after the fact.
- **Undo agent sessions with rollbacks.** nono can snapshot the filesystem before Hermes runs and give you a per-file diff and interactive restore prompt when it exits, so you can reverse changes without having to work out what the agent touched by hand.


## Installation

### Installing nono

Installation instructions are available on [nono's documentation site](https://nono.sh/docs), after intstalling nono, you can install the hermes plugin.

### Installing the hermes plugin

nono provides an official hermes profile on the nono registry. Should you need to, need to you can then extend from this profile and customize it to your needs. Most of you will be wanting to use credential injection and other features, as well as add your own workspace folders and other customizations, so extending the profile is likely the way to go for most users. This is covered in the Custom profiles section below.

The following command both retrieves the `always-further/hermes` plugin and runs hermes inside the sandbox:

```bash
  nono run --profile always-further/hermes --allow-cwd -- hermes
```

Should you need to pull the package in a seperate step, you can do so with:

```bash
  nono pull always-further/hermes
```

### First-run grants prompt

On first run, nono may detect paths that Hermes needs but that the base profile doesn't cover — your shell config, a tool on a non-standard path, etc. When this happens you'll see a prompt like:

```
Sandbox denial: 4 paths blocked.
  ~/.config/gh (read)
  ~/.config/nono/packages/always-further/hermes/plugin/nono-sandbox/__pycache__ (write)
  ~/dev/dotfiles/zsh (read)
  /usr/local/sbin (read)

[nono] Choose suppress to keep denying all listed paths and stop future save suggestions.
Save suggestions to a user profile? [g] grant / [s] suppress / [Enter] skip:
```

- **`g` (grant)** — saves the extra path grants to a user profile. nono will prompt you for a name; use the same name you plan to use for your custom credential profile (e.g. `hermes-agent`), or extend from it later so both sets of grants live in one place. If you create a separate grants profile here, remember to pass it alongside your credential profile: `nono run --profile hermes-agent --profile hermes-grants -- hermes`.
- **`s` (suppress)** — stops nono from suggesting these paths in future. The paths remain denied.
- **Enter (skip)** — skips saving for now. The paths stay denied this session but you'll be prompted again next time.

If you already know you want a custom profile, the cleanest approach is to skip (`Enter`) here and add the paths manually to your child profile's `filesystem.allow` block instead, so everything is in one place.

## Activating the plugin

Plugin activation happens automatically on first run, the package symlinks itself into:

```text
~/.hermes/plugins/nono-sandbox
```

and merges this into `~/.hermes/config.yaml`:

```yaml
plugins:
  enabled:
    - nono-sandbox
```

## Custom profiles

To create your own custom profile that extends the base `always-further/hermes` profile, use the `nono profile init` command with the `--extends` flag. This allows you to inherit from the base profile while customizing specific aspects such as credential routes and network filtering.

> If you already created a profile via the first-run grants prompt, use that same name here — `nono profile init` will extend it rather than creating a second one.

```bash
nono profile init hermes-agent --extends always-further/hermes --full
```

This will create a `~/.config/nono/profile/hermes-agent.json` file that you can then customize to your needs. The `--full` flag ensures that the generated profile includes all sections, making it easier to see what you can customize.

## Credential Protection

nono protects API keys using a **phantom credential** model. Rather than passing your real key into the sandbox, nono generates a short-lived random token and injects that into Hermes instead. When Hermes makes an outbound API call carrying the phantom token, nono's proxy intercepts the request, validates the token, fetches the real key from your system keystore (macOS Keychain, Linux Secret Service, 1Password, etc.), and swaps it in before the request leaves the machine. The real key is never visible to the sandboxed process, so even if Hermes or a tool it runs were compromised, an attacker would obtain only the useless phantom — not the credential itself.

> **Do not store API keys in `~/.hermes/.env`.** Hermes' own documentation suggests this as a general approach, but doing so places the real key directly in Hermes' environment and bypasses nono's phantom credential protection entirely. Keep keys in nono's keychain (or a URI ref source) and let nono inject them.

### Built-in providers

The base `hermes` profile does not enable provider credentials by default. This avoids warnings for unused providers from becoming part of the session boundary.

The following providers are built in and ready to use. How you store the key depends on the route — some read from the system keychain, others read from an environment variable in nono's own process:

| Route Name  | Provider   | Storage method       | Key name / account  |
|-------------|------------|----------------------|---------------------|
| `openai`    | OpenAI     | nono keychain        | `OPENAI_API_KEY`    |
| `anthropic` | Anthropic  | nono keychain        | `ANTHROPIC_API_KEY` |
| `gemini`    | Gemini     | nono keychain        | `GOOGLE_API_KEY`    |
| `github`    | GitHub     | nono keychain        | `GITHUB_TOKEN`      |
| `gitlab`    | GitLab     | nono keychain        | `GITLAB_TOKEN`      |

Store each key in the nono keychain service using the exact account name shown in the table above.

#### Step 1 — store the key

**For keychain-backed routes** (`openai`, `gemini`):

macOS Keychain:

macOS Keychain:

```bash
security add-generic-password -U -s "nono" -a "OPENAI_API_KEY" -w
security add-generic-password -U -s "nono" -a "ANTHROPIC_API_KEY" -w
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w
security add-generic-password -U -s "nono" -a "GITHUB_TOKEN" -w
security add-generic-password -U -s "nono" -a "GITLAB_TOKEN" -w
```

Keep `-w` last so macOS prompts for the value instead of recording it in shell history.

Linux Secret Service:

```bash
secret-tool store --label="nono: OPENAI_API_KEY" \
  service nono username OPENAI_API_KEY target default

secret-tool store --label="nono: GOOGLE_API_KEY" \
  service nono username GOOGLE_API_KEY target default
```

On Linux this requires a running Secret Service provider such as GNOME Keyring or KWallet. In SSH-only or headless environments, check the nono credential docs before choosing a storage backend.

If your keys live in 1Password, Apple Passwords, a file, or an environment variable, you can override any built-in route using `custom_credentials` — see the [Custom providers](#custom-providers) section below for field details and examples.

For the full credential URI ref model (`op://`, `apple-password://`, `file://`, `env://`), see:

- https://nono.sh/docs/cli/features/credential-injection

#### Step 2 — enable the route in your profile

Open your child profile (`~/.config/nono/profile/hermes-agent.json`) and add the route name to the `credentials` array in the `network` block:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["anthropic"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {}
}
```

You can enable multiple providers at once:

```json
"credentials": ["anthropic", "github"]
```

Then run Hermes with your child profile:

```bash
nono run --profile hermes-agent -- hermes
```

### Custom providers

If the provider you need isn't in the built-in list, you can add it with `custom_credentials`. The same phantom-token swap mechanism applies — you define the upstream URL, the keychain account to use, and optionally which API endpoints are permitted.

This example adds [OpenRouter](https://openrouter.ai) — an OpenAI-compatible model-routing API that authenticates with `Authorization: Bearer <key>`.

#### How phantom credentials and endpoint rules work

nono generates a phantom token and injects it into Hermes as an environment variable. When Hermes makes an outbound call, the proxy validates the phantom, fetches the real key from the keystore, and swaps it in before the request leaves the machine.

`endpoint_rules` adds an L7 allow-list on top of that. Each rule is a `{"method", "path"}` pair. When the list is non-empty the proxy rejects any request that doesn't match — even if the phantom token is valid. This prevents a compromised agent from using the credential to reach billing endpoints, account management, or any other API surface you haven't explicitly declared.

#### Step 1 — store the key

Store the key in your system keyring under the account name you'll reference in the profile (`OPENROUTER_API_KEY` here).

macOS Keychain:

```bash
security add-generic-password -U -s "nono" -a "OPENROUTER_API_KEY" -w
```

Linux Secret Service:

```bash
secret-tool store --label="nono: OPENROUTER_API_KEY" \
  service nono username OPENROUTER_API_KEY target default
```

If the key lives somewhere other than the system keyring, point `credential_key` at it with a URI ref instead:

```json
"credential_key": "env://OPENROUTER_API_KEY"
```
Reads the key from `OPENROUTER_API_KEY` in nono's own environment. `env_var` is not required for this form.

```json
"credential_key": "op://Personal/OpenRouter/credential",
"env_var": "OPENROUTER_API_KEY"
```
Fetches the key from 1Password at runtime. `env_var` is required for `op://` so nono knows which variable to inject into the sandbox.

```json
"credential_key": "file:///run/secrets/openrouter.key",
"env_var": "OPENROUTER_API_KEY"
```
Reads the key from a file. `env_var` is required for `file://`.

#### Step 2 — add the route to your profile

Open your child profile (`~/.config/nono/profile/hermes-agent.json`) and update the `network` block:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["openrouter"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {
    "openrouter": {
      "upstream": "https://openrouter.ai",
      "credential_key": "OPENROUTER_API_KEY",
      "env_var": "OPENROUTER_API_KEY",
      "endpoint_rules": [
        { "method": "POST", "path": "/api/v1/chat/completions" },
        { "method": "GET",  "path": "/api/v1/models" }
      ]
    }
  }
}
```

The map key (`"openrouter"`) is the route name. **It must also appear in the `credentials` array** — nono only activates routes explicitly listed there. `inject_header` and `credential_format` are omitted here because the defaults (`"Authorization"` and `"Bearer {}"`) already match what OpenRouter expects.

#### Field reference

| Field               | Required                                   | Default      | Description |
|---------------------|--------------------------------------------|--------------|-------------|
| `upstream`          | yes                                        | —            | HTTPS base URL of the provider. HTTP is only permitted for loopback addresses. |
| `credential_key`    | yes                                        | —            | Keystore account name or a URI ref: `env://VAR`, `op://vault/item/field`, `apple-password://server/account`, `file:///path`, or `keyring://service/account`. |
| `env_var`           | required for `op://`, `apple-password://`, `file://` | — | Environment variable injected into the sandbox with the phantom token. The SDK reads this name; nono's proxy validates and replaces it with the real key before forwarding upstream. Not required when `credential_key` is `env://`. |
| `inject_mode`       | no                                         | `"header"`   | One of: `"header"`, `"url_path"`, `"query_param"`, `"basic_auth"`. |
| `inject_header`     | no (header mode)                           | `"Authorization"` | HTTP header to inject the credential into. |
| `credential_format` | no (header mode)                           | `"Bearer {}"` for `Authorization`; `"{}"` for others | Format string with `{}` placeholder for the credential value. |
| `path_pattern`      | url_path mode                              | —            | URL path pattern containing `{}` where the phantom token appears. |
| `path_replacement`  | no (url_path mode)                         | same as `path_pattern` | Replacement pattern for the outbound URL path. |
| `query_param_name`  | query_param mode                           | —            | Query parameter name carrying the phantom token. |
| `endpoint_rules`    | no                                         | `[]` (allow all) | L7 allow-list of `{"method": "...", "path": "..."}` objects. Default-deny when non-empty. |
| `proxy`             | no                                         | —            | Overrides applied only to phantom token parsing on the proxy side. Outbound injection continues to use top-level fields. |
| `tls_ca`            | no                                         | —            | Path to a PEM-encoded CA certificate for upstreams with a private or self-signed CA. |
| `tls_client_cert`   | no                                         | —            | Path to a PEM-encoded client certificate for mTLS. Must be set together with `tls_client_key`. |
| `tls_client_key`    | no                                         | —            | Path to the PEM-encoded private key matching `tls_client_cert`. |

Run Hermes with your child profile:

```bash
nono run --profile hermes-agent -- hermes
```

## Audit Logging

Every nono session produces an append-only audit log recording what Hermes did: the command and arguments (with secrets redacted), start/end timestamps, exit code, capability decisions, network events, and the filesystem paths it touched. Logs are written to `~/.nono/audit/` as `session.json` and `audit-events.ndjson`, and are tamper-evident by default.

```bash
nono audit list                          # all sessions
nono audit list --today                  # today only
nono audit list --command hermes         # filter by command
nono audit show <session-id>             # inspect a session
nono audit show <session-id> --json      # machine-readable
nono audit verify <session-id>           # verify log integrity
nono audit cleanup                       # remove old sessions
```

To disable audit logging for a session, pass `--no-audit`:

```bash
nono run --profile hermes-agent --no-audit -- hermes
```

If you want the session log but don't need tamper-evident protection:

```bash
nono run --profile hermes-agent --no-audit-integrity -- hermes
```

If you add secrets-adjacent flags to your Hermes invocation, you can extend nono's redaction rules so they never appear in the log. Add to `~/.config/nono/config.toml`:

```toml
[redaction]
extra_flags = ["--private-token", "--pat"]
extra_headers = ["Private-Token"]
extra_query_keys = ["sig", "signature"]
```

## Rollbacks

nono can snapshot the filesystem before Hermes runs and let you selectively restore any files it changed or deleted. This is useful when you want to review or undo an agent session without having to figure out what changed by hand.

```bash
nono run --rollback --profile hermes-agent -- hermes
```

With `--rollback` active, nono takes a baseline snapshot before execution and a final snapshot after. When Hermes exits, if any files were modified or deleted you get an interactive review showing a per-file diff and a prompt to restore whichever files you want back.

Snapshots are stored in `~/.nono/rollbacks/<session-id>/` using SHA-256 content-addressable storage with Merkle tree verification. On macOS (APFS) this is copy-on-write via `clonefile()`, so storage cost is low for sessions with few changes. nono keeps a maximum of 10 sessions and 5 GB by default.

```bash
nono rollback list                        # past sessions grouped by project
nono rollback show <id> --diff            # inspect what changed
nono rollback restore <id>                # interactive restore
nono rollback restore <id> --dry-run      # preview without writing
nono rollback verify <id>                 # check Merkle integrity
nono rollback cleanup --older-than 7      # remove sessions older than 7 days
```

To suppress the interactive review prompt (for scripting):

```bash
nono run --rollback --no-rollback-prompt --profile hermes-agent -- hermes
```

Exclude noisy paths from snapshot tracking in your child profile:

```json
"rollback": {
  "exclude_patterns": ["node_modules", ".next", "__pycache__"],
  "exclude_globs": ["*.tmp.[0-9]*.[0-9]*"]
}
```

`.gitignore` entries in the working directory are also respected automatically.

## nono commands

The plugin then exposes `/nono-status` and the `nono_status` tool after Hermes reloads.

Inside a running Hermes sandbox, use `nono why --self` so the query uses the sandbox context for any particular file or network access check:

```bash
nono why --self --path /path/to/some/file --op read
```



### Agent Profile Expansion and Promotion

When a sandbox denial occurs, the agent can draft profile changes, but it cannot directly edit active profiles under `~/.config/nono/profiles`. This keeps policy changes behind an explicit user promotion step. When the agent drafts a profile change, it writes the proposed profile to `~/.config/nono/drafts/<name>.json`. Review the draft, then promote it to make it active:

```bash
nono profile validate --draft hermes-agent
nono profile promote hermes-agent
```



### Uninstalling the plugin

```bash
nono remove always-further/hermes
```

## Complaints about __pycache__

`PYTHONDONTWRITEBYTECODE=1` prevents Python from trying to create `__pycache__` under the signed, read-only package store while Hermes imports the plugin. 

Do not grant write access to `~/.config/nono/packages/.../plugin/nono-sandbox` to silence that cache write.

When checking capabilities from outside Hermes, include the profile context:

```bash
nono why --profile hermes --path ~/.config/nono/packages/<ns>/hermes/plugin/nono-sandbox/__init__.py --op read
```
