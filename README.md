# Hermes Agent Skills (OSS)

Reusable skills for Hermes Agent (by Nous Research) that can be adapted to any agent framework.

## Skills

| Skill | Lines | Description |
|-------|-------|-------------|
| fleet-operations | 253 | Audit, exploit, or back up multi-node fleets over SSH/Tailscale |
| grounded-citations | 232 | Ground answers and documents in cited, verifiable sources |
| local-rag | 125 | Build/operate local RAG with Ollama embeddings and Qdrant |

## Usage

Copy any skill directory to `~/.hermes/profiles/<profile>/skills/<category>/<name>/` and Hermes will auto-discover it.

## License

MIT
