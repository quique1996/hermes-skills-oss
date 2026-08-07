# MCP server inventory, audit & hardening (root config.yaml)

Session 2026-08-05. 19 MCP servers lived in the ROOT `~/.hermes/config.yaml`
`mcp_servers:` section (the DEFAULT profile's gateway loads these). Audit +
hardening cut the active surface 19 → 15, pinned mutable versions, and moved a
literal token out of the config.

## Inventory extraction (names only — never print secret values)

The config mixes real servers with structural keys, so a naive key dump over-
counts. Parse with python and keep only dict-valued entries that look like
servers, or diff against known structure keys (args/command/env/name/servers).
Real server entries carry `command:`/`url:` + optionally `env:`/`tools:`.

Also check: `~/.hermes/mcp.json`, `~/.hermes/mcp/*.json` (legacy), `~/.hermes/
mcp-config.yaml`, npm globals (`npm ls -g --depth=0 | grep -i mcp`), and
`mcp-installs/`.

## Hermes CLI scope gotcha

- `hermes config get/set/unset` operate on the PROFILE config
  (`~/.hermes/profiles/<name>/config.yaml`) ONLY. Root config keys
  (`mcp_servers`, `model_aliases`, ...) report "Config key not set" via the
  profile CLI — edit the root file directly (backup first:
  `cp ~/.hermes/config.yaml ~/.hermes/config.yaml.bak-<topic>-<date>`).
- `hermes mcp test <name>` also resolves against the PROFILE config — it will
  say "Server 'qdrant' not found" for root-config servers. Test those by
  spawning the server + a stdio MCP client (see rag-qdrant-mcp.md) or register
  the server in the profile config.

## What a healthy entry looks like (vs the smells)

Good: `${VAR}` env references (secrets NOT in the file), `tools: include/exclude`
whitelists (8 of 19 already limited to 1 tool), version pins (`blender-mcp==1.6.4`).
Smells found: `@latest` tags (mutable supply chain), unpinned `npx -y` packages,
remote URL MCPs with LITERAL bearer tokens in the config (MCP03), and dead
entries with no command (remote-OAuth leftovers) still `enabled: true`.

## Hardening sequence executed

1. `cp` backup of root config.
2. Disable unused: set `enabled: false` (linear remote-OAuth, unused) — verify
   docker/vercel/unreal-engine were already `enabled: false` (the audit had
   flagged docker as critical; it was already off — always re-check before
   acting on an audit flag).
3. Move literal secrets: python regex `(Authorization:\s*Bearer\s+)(\S+)` →
   append `XAPI_TOKEN=<value>` to `~/.hermes/.env` (chmod 600), replace config
   with `${XAPI_TOKEN}`. Never print the value.
4. Pin versions: `npm view <pkg> version` → replace `@latest`/unpinned arg with
   `@<exact>` in `args`.
5. Verify: YAML parses, enabled count == expected, no `@latest`, no literal
   `Bearer <long-token>` in the file, backup exists. Re-verify after ANY later
   edit (fresh evidence rule).

## OWASP MCP Top 10 mapping (quick reference)

- Supply chain (pinning/@latest) — the dominant risk: one compromised package
  exposes the keys of every sibling MCP in the same process (78.3% attack
  cascade stat from 2026 research).
- Excessive agency — docker/browser MCPs without tool allowlists or human-in-
  the-loop.
- Secret handling — literal tokens in config vs `${VAR}` env refs.
- Dead surface — disabled entries cost nothing to leave, but `enabled: true`
  dead entries (no command) are free attack surface; disable them.
