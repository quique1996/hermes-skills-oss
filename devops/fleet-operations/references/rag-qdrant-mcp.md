# RAG over Qdrant (named-vector collections) — debugging saga + working pattern

Session 2026-08-05. Goal: make Hermes able to query the "second brain" (Qdrant
`hermes_brain` on Mini, ~3.7k points) via MCP. The third-party MCP was broken;
the fix was a ~40-line custom FastMCP server. Root causes + working recipe below.

## The two real root causes (both had to be found)

1. **Latest PyPI `qdrant-mcp-server` crashes at import**: `transformers`
   dependency_versions_check fails in the uv-resolved env → server exits on
   startup → MCP client sees "Connection closed". Confirm by running the server
   binary alone with `< /dev/null` and reading stderr (no MCP client needed).
2. **The search request shape**: for collections configured with a NAMED vector
   (e.g. `fast-all-minilm-l6-v2`), Qdrant 1.18 rejects both
   `{"vector": [...], "using": "name"}` and `{"vector": {"<name>": [...]}}`
   with `400 Bad Request` / "Not existing vector name". The ONLY working form:
   ```json
   {"vector": {"name": "fast-all-minilm-l6-v2", "vector": [384 floats]},
    "limit": 3, "with_payload": true}
   ```
   `POST /collections/<c>/points/scroll` works for payload inspection; the
   collection payload carries the note text under `payload.document`.

## Embedding can live on ANY node — co-location is not required

The query embedding just needs the SAME model weights as the indexed vectors
(same model name = same vector space). Mini's Ollama is the trouble child
(localhost-only, TCC) — so we pulled `all-minilm` (45 MB) on GEEKOM, whose
ollama already serves 0.0.0.0:11434, and pointed the MCP there. Verify dims
match the collection (384) before searching.

## macOS TCC: launchd agents cannot read external volumes

Symptom: `ollama serve` under a LaunchAgent binds `*:11434` (lsof confirms) but
freezes mid-init — main thread stuck in `open()` (sample shows it), log stops
right after "Ollama cloud disabled", and even loopback HTTP returns nothing.
Cause: macOS TCC blocks launchd-spawned processes from `/Volumes/*` without a
Full Disk Access grant; `open()` hangs instead of failing (headless, no prompt).

Confirm cheaply with a throwaway agent that `ls`s the volume:
```xml
<plist version="1.0"><dict>
  <key>Label</key><string>com.tcc.test</string>
  <key>ProgramArguments</key><array><string>/tmp/tcc-test.sh</string></array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
</dict></plist>
```
→ output `ls: /Volumes/Workspace/...: Operation not permitted` = TCC confirmed.

Also learned: `Ollama.app` binds **localhost only** and ignores
`launchctl setenv OLLAMA_HOST`; brew `ollama serve` from an SSH shell works
(sshd context has TCC), a manual `OLLAMA_HOST=0.0.0.0:11434 ollama serve` works,
but the same command under launchd freezes on the external models dir. Don't
fight it: host the embedding on a node that already serves 0.0.0.0.

## Working pattern: minimal FastMCP server (the fix that stuck)

`~/.hermes/scripts/qdrant-rag-mcp.py` — FastMCP from the `mcp` package (already
in the hermes venv), one tool `search(query, limit)`:
1. `POST {OLLAMA_URL}/api/embeddings` with `{"model": "all-minilm", "prompt": q}`
2. `POST {QDRANT_URL}/collections/{c}/points/search` with the named form above
3. Format `[i] score=... src=...\n<document[:800]>` per hit.

Env-driven (OLLAMA_URL, QDRANT_URL, COLLECTION_NAME, QDRANT_VECTOR_NAME,
EMBEDDING_MODEL, QDRANT_SEARCH_LIMIT) — mirrors the old config so the MCP entry
kept its env block. Register in root config.yaml:
```yaml
  qdrant:
    args: [/Users/quiquebedolla/.hermes/scripts/qdrant-rag-mcp.py]
    command: /Users/quiquebedolla/.hermes/hermes-agent/venv/bin/python
    enabled: true
```

Test end-to-end WITHOUT touching config: spawn the server with a stdio MCP
client (hermes venv python):
```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
params = StdioServerParameters(command=PY, args=[SCRIPT], env={**os.environ, ...})
# await s.initialize(); tools = await s.list_tools(); await s.call_tool("search", {...})
```

## Diagnostics ladder used (in order)

1. Collection info: `GET /collections/hermes_brain` (dims, name, points, status).
2. Embedding reachability: `curl http://<host>:11434/api/version` (instant) vs
   `/api/tags` (SLOW with cloud models — don't use for timeouts).
3. TCP vs HTTP: `nc -vz -w 5 <ip> 11434` — connects while HTTP stalls = server
   accepts but never responds (frozen), NOT firewall/ACL.
4. Frozen process: `sample <pid> 1` (main thread syscall, e.g. stuck in
   `open()`), `lsof -p <pid>` (open FDs).
5. Firewall check BEFORE blaming it: `socketfilterfw --getappblocked <bin>`
   ("Incoming connection ... is permitted") + `--listapps`.
6. launchd domain env: `launchctl print gui/$(id -u) | grep OLLAMA`; setenv:
   `launchctl getenv <VAR>`.
