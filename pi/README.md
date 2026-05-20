<p align="center">
  <img src="./assets/logo.png" alt="nono codex" width="500" />
</p>


`pi` is a nono package for [Pi Coding Agent](https://pi.dev).

It installs:

- a `pi` nono profile for running Pi inside an OS-enforced sandbox
- a Pi package that loads a `nono-sandbox` extension and skill
- wiring that adds the installed pack directory to `~/.pi/agent/settings.json`

## Install

```bash
nono pull always-further/pi
```

Or let nono prompt you on first use:

```bash
nono run --profile pi -- pi
```

After pulling, the pack adds this package to Pi's global settings:

```json
{
  "packages": [
    { "source": "~/.config/nono/packages/always-further/pi" }
  ]
}
```

The installed package loads:

- `extensions/nono-sandbox.ts`
- `skills/nono-sandbox/SKILL.md`

## Run

```bash
nono run --profile pi -- pi
```

For a custom profile:

```bash
nono profile init pi-agent --extends always-further/pi --full
nono run --profile pi-agent -- pi
```

Use a custom profile for credential routes, extra filesystem grants, or local project policy.

## Credential protection

The base profile defines provider routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab, but enables none by default. Enable only the routes you need in a child profile:

```json
"network": {
  "credentials": ["anthropic"]
}
```

Store keys in the nono keychain using these account names:

```bash
security add-generic-password -U -s "nono" -a "OPENAI_API_KEY" -w
security add-generic-password -U -s "nono" -a "ANTHROPIC_API_KEY" -w
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w
security add-generic-password -U -s "nono" -a "GITHUB_TOKEN" -w
security add-generic-password -U -s "nono" -a "GITLAB_TOKEN" -w
```

Pi can also store API keys in `~/.pi/agent/auth.json`, but that file must be readable by Pi inside the sandbox. Prefer nono credential routes for API keys that should not be visible to the agent process.

## Sandbox denials

When Pi is running inside nono and a tool result looks like a sandbox denial, the extension appends diagnostic guidance to the failed tool result and notifies the user. The bundled skill teaches the agent to run:

```bash
nono why --self --path /blocked/path --op read
```

Then it should present exactly two options:

- one-off restart with `nono run --profile pi --allow /path/to/needed -- pi`
- persistent profile draft in `~/.config/nono/profile-drafts`, promoted by the user with `nono profile promote`

Do not fix nono denials with `sudo`, `chmod`, `chown`, Full Disk Access, or Pi approvals. Those do not change the outer OS sandbox.
