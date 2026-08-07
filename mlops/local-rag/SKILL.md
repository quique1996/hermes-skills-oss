---
name: local-rag
description: Build/operate local RAG with Ollama embeddings and Qdrant.
version: 1.1.0
author: stella
license: MIT
tags: [rag, ollama, qdrant, embeddings, nous, llm-infra, mlops]
related_skills: [serving-llms-vllm, llama-cpp, huggingface-hub, homelab-rag, fleet-rag]
---

# Local / Distributed RAG Pipeline

Use when building or operating a RAG system where documents are embedded locally and
retrieved at query time to ground an LLM. Common with Ollama (embed+generate) on one
host and Qdrant on another, queried from a third client.

## When to use
- User wants a "tutor/expert bot" grounded in their own docs/codebase.
- Building a knowledge base over docs that change (scrape → embed → upsert → retrieve).
- Wiring a local LLM (Nous, OpenRouter, Ollama) as the generator behind retrieval.
- Anything mentioning RAG, vector store, embeddings, semantic search, Qdrant, Chroma.

## Architecture (proven)
```
client (ask) ──▶ embed via Ollama (nomic-embed-text, 768d)
              ──▶ retrieve top-k from Qdrant (Cosine, 768d)
              ──▶ LLM (Nous / OpenRouter / Ollama) answers with retrieved context
```
Decoupling embed/infer host from the vector store host is normal on a multi-node fleet.
See `references/fleet-topology-example.md` for a real 3-node layout.

## Web acquisition (the ingest side)
The ingest script must fetch clean page text. Two verified patterns:

1. **Antigravity (`agy`) — PREFERRED.** Headless, deterministic, failure-detectable.
   ```bash
   agy -p "Fetch <url> and return ONLY the clean markdown body text, nothing else. \
   If you cannot fetch it, reply exactly with the single word FETCH_FAILED." \
   --dangerously-skip-permissions --output-format json
   ```
   Parse `json.loads(stdout)["response"]`. On `status != "SUCCESS"`, empty body, or a
   `FETCH_FAILED` sentinel → RAISE so the source is flagged broken (never embedded as
   if it were real content). Full pattern + reason in `references/acquisition-agy.md`.
   **WHY NOT `hermes chat -q`**: the wrapper returns the agent's natural-language error
   message (">200 chars") and the ingest loop accepts it as valid markdown → silently
   embeds garbage. Verified bug, fixed by switching to `agy` JSON.
2. **Firecrawl REST** (if `FIRECRAWL_API_KEY` set): `POST https://api.firecrawl.dev/v1/scrape`.
   Deterministic, same failure semantics. Use when `agy`/Portal is unavailable.
3. **Regex fallback** (`re.sub("<[^>]+>"," ",html)`): last resort, noisy — only when the
   above are unavailable. Never the primary acquirer for a quality corpus.

Run acquisition in parallel: `ThreadPoolExecutor(max_workers=6)` over all sources, then
embed serially. `agy` per-URL is 10–30s; parallel ~4x faster over 13 sources.

## Source curation (pre-ingest verification)

Before acquiring, assemble and **verify** the candidate URL list so you never ingest
a dead or link-rot-prone source. Canonical method, pitfalls, and domain gotchas
(Godot GDExtension path move, Khronos wiki 403, urllib 406) are in
`references/source-verification.md`. Rule of thumb: `curl -sI -L --max-time 15`
must return `200` (or a `30x` that resolves to `200`); reject `404/403/000`.

## Workflow
1. **Create the collection** in Qdrant with the EXACT dim your embedder produces.
   ```bash
   curl -X PUT http://QDRANT:6333/collections/NAME \
     -H 'Content-Type: application/json' \
     -d '{"vectors":{"size":768,"distance":"Cosine"}}'
   ```
2. **Install a 768-dim embedder** on the Ollama host. `nomic-embed-text` is preferred
   over `all-minilm` (384d). `ollama pull nomic-embed-text`.
3. **Ingest**: fetch docs → strip HTML → chunk → embed → upsert to Qdrant.
   Run as a cron job for always-current corpora.
4. **Query**: embed question → search → inject top-k payloads as LLM context.

## Pitfalls (verified)
- **WRONG NOUS ENDPOINT.** `api.nousresearch.com` does NOT resolve. Correct base:
  `https://inference-api.nousresearch.com/v1` (key prefix `sk-nous-...`). Details in
  `references/nous-portal-api.md`.
- **VALID MODELS (Nous Portal).** `tencent/hy3:free` is a working free chat model on the
  inference-api endpoint (user-selected, verified end-to-end). `Hermes-4-405B` also works.
  Set `NOUS_MODEL` accordingly; the env default should point at the live inference-api
  host, never `api.nousresearch.com`.
- **IDEMPOTENT RE-INGEST.** Use deterministic point IDs (`int(sha256(f"{url}#{i}")[:15],16)`)
  so re-running ingestion upserts in place instead of duplicating. The `--force` flag
  re-embeds everything; otherwise skip unchanged sources via a per-collection state hash.
- **STATE FILE NAMESPACING (multi-ingester host).** When two ingest scripts run on the
  same host, a shared `.ingest_state.json` COLLIDES (cross-contamination skips real
  sources). Namespace it: `.ingest_state_{COLLECTION}.json`. Verified bug + fix.
- **DRY-RUN MUST NOT PERSIST STATE.** If `save_state()` runs before the dry-run guard,
  a `--dry-run` writes the hash cache and the NEXT real run sees "unchanged" → skips and
  never upserts. Put `save_state(state)` AFTER the `if args.dry_run: return` guard.
  Verified bug + fix (cost: a silently-empty collection).
- **PRE-INGEST URL CHECK USES curl, NOT urllib.** `urllib.request` gets `406` from
  some hosts (e.g. `learnopengl.com`) that serve `200` to curl — a false dead-link.
  Verify candidates with `curl -sI -L --max-time 15` (details in
  `references/source-verification.md`). Also: prefer repo roots/solid doc pages over
  raw GitHub file paths (they 404 on rename/move).
- **SOURCE-ROT SILENCE.** A cron ingest that 404s a source stays silent → stale corpus.
  Implement `alert_broken()` that writes `.ingest_alerts.log` and (optionally) a Telegram
  message when any source fails to fetch. Call it on ALL exit paths (empty batch too).
- **PARALLEL FETCH.** Acquire all sources concurrently with `ThreadPoolExecutor`; embed
  serially after. Verified ~4x faster over 13 sources.
- **EMBEDDER CONTEXT LIMIT.** `nomic-embed-text` 500s on long input
  ("input length exceeds the context length"). Chunk by **characters (~1400, overlap
  150)**, not words. Recipe in `references/nomic-embed-text.md`.
- **DIM MISMATCH REJECTS UPSERT.** Embedder 384d vs collection 768d (or vice-versa)
  fails the upsert. Match dims exactly.
- **EMBED MODEL NAME MATTERS.** Use the Ollama tag as the API model string.
  `all-minilm` = 384d; won't fit a 768d collection.
- **VERIFY AD-HOC AFTER EVERY EDIT.** The runtime flags "stale evidence" when a changed
  file's prior verification predates the edit. After editing any ingest/ask script, run a
  fresh ad-hoc check (compile + live count + retrieve + e2e) and clean up the temp script.
  Never reuse a prior green result across an edit.
- **ICMP blocked, TCP open.** Test Qdrant via `:6333/count`, not ping.

## Secure API-key handling
- Never paste the key into a command line. Use a `--set-key` mode or a `.env` file.
- `.env` must be gitignored and `chmod 600`.
- Loader reads `.env` at startup, sets `os.environ`, never prints the key.
- Checklist in `references/secure-key-handling.md`.

## Verification (mandatory before "done")
Run an ad-hoc check (compile, live count, retrieve) — never claim success on a plan.
See `references/verification-recipe.md`.
