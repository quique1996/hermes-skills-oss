# Hermes config & limits (discovered 2026-08-05)

Verified against hermes-agent v0.20.0 source and CLI. For fleet-ops where Hermes must be wired to local/remote endpoints.

## Profile config is the active config

- Running under a profile (e.g. stella), `hermes config path` → `~/.hermes/profiles/<name>/config.yaml`.
- Editing `~/.hermes/config.yaml` (the global/default one) has NO effect on the profile session — `hermes config get providers` returns `{}` even though the global file has providers.
- **Never hand-edit config.yaml** (house rule): a stray indent breaks the live gateway. Use `hermes config set <dotted.key> <value>` and `hermes config unset <dotted.key>`. `hermes config check` validates (config version 33 at v0.20.0).

## Registering a custom OpenAI-compatible endpoint (local Ollama)

- `--provider` accepts "Built-in or a user-defined name from `providers:` in config.yaml" (per `hermes chat --help`). So define in the PROFILE config:
  ```
  hermes config set providers.geekom-ollama.api_key ollama
  hermes config set providers.geekom-ollama.base_url http://<host>:11434/v1
  hermes config set providers.geekom-ollama.models '["qwen3:8b",...]'
  ```
- `hermes config set` writes to the ACTIVE profile config (verified: wrote to profiles/stella/config.yaml).
- Model aliases (`model.aliases.<name>` with `provider: custom`, `base_url`) resolve ONLY via `/model <alias>` in sessions — `hermes chat -m <alias>` does NOT resolve them (404). For CLI one-shots use `--provider`.

## 64K context hard limit

- `agent/agent_init.py` (MINIMUM_CONTEXT_LENGTH): agent sessions are REJECTED when the model's context window < 64K.
- Ollama 3-8B models on a 16GB box report 40K or less and can't serve 64K anyway (KV cache 7-13GB). They remain usable via the OpenAI-compatible API (`/v1/chat/completions`) for garak, evals, batch scripts.
- The only code-level bypass is `provider == "lmstudio"` + explicit `model.context_length` — it LIES about real context (Ollama num_ctx default 4096 → silent truncation). Do not use it; fail closed.
- Consequence: local models serve API-level consumers, not Hermes chat. Cloud inference (ollama-cloud) is the production path.

## Other quirks hit in practice

- `hermes config get providers` returns `{}` on a profile whose config lacks a providers block — the global file's providers are invisible to the profile CLI.
- `hermes model` requires an interactive terminal (fails in pipes/ssh).
- `hermes chat -Q --provider geekom-ollama -m qwen3:8b` with a sub-64K model fails at agent init with the explicit 64K error — that error message is the CONFIRMATION that the provider was recognized (vs "Unknown provider" = not registered).
