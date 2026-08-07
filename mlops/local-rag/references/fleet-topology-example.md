# Real 3-node RAG topology (BGW tutor, verified 2026-08-06)

User's actual fleet, roles corrected from a proposal that had them inverted.

| Node | Real role | Evidence |
|---|---|---|
| Mac mini M4 (100.90.88.5) | **Vector store** — Qdrant native on :6333 (NOT Docker; `docker ps`=0). ~101 GB free. | `curl :6333/collections` returned agent_memory, hermes_brain, kg_full (5411 pts), etc. |
| GEEKOM Ryzen 9 (100.123.17.12) | **Inference + Embeddings + Ingestion** — Ollama :11434 with qwen3:8b, nomic-embed-text (768d), llama3.2:3b, qwen2.5:3b. Docker runs wazuh + labs. | `curl :11434/api/tags`. ~9 GiB free RAM, 875 GB disk. |
| MacBook Air | **Client/dev** — runs the ask script, embeds via GEEKOM, retrieves from Mini, calls Nous. | local session host. |

## Flow
```
Air (bgw_ask.py) ──embed──▶ GEEKOM Ollama (nomic-embed-text, 768d)
                     ──retrieve──▶ Mini Qdrant (bgw_knowledge, 768d, Cosine)
                     ──context──▶ Nous (inference-api.nousresearch.com) ──answer
```

## Lessons
- Measure the fleet before trusting a plan's assumed roles. The proposal said "Mini =
  Ollama inference, GEEKOM = Vector DB" — reality was the opposite. Always probe
  `:11434` and `:6333` before assigning roles.
- LAN latency Air→GEEKOM ≈ 9.7 ms; plenty for sync embed+retrieve.
- Mini Qdrant is native (not containerized): verify it has an auto-start on reboot
  (launchd/plist) or the vector store is lost on Mini restart.
- Don't expose `:6333`/Ollama beyond the Tailscale LAN.
