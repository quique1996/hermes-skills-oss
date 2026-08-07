# Web acquisition with Antigravity (`agy`)

## Why `agy` and not `hermes chat`
A RAG ingest loop calls a web fetcher per source. The naive choice was:

```python
r = subprocess.run(["hermes","chat","-q", prompt], ...)
if r.returncode == 0 and len(r.stdout.strip()) > 200:
    return r.stdout   # BUG: accepts error text as content
```

`hermes chat` on a dead/unreachable URL returns the agent's natural-language apology
("I couldn't reach that page…") which is >200 chars → the loop treats it as VALID
markdown and embeds garbage. The corpus silently fills with error prose. Verified bug
(this session): a `127.0.0.1:9/dead` URL produced 2 "chunks" and was counted as a changed
source. No alert fired.

## The fix: `agy` headless JSON + FETCH_FAILED sentinel
`agy` (Antigravity CLI, in routing policy as the web-research tool) runs headless and
returns structured JSON:

```bash
agy -p "Fetch <url> and return ONLY the clean markdown body text, nothing else. \
If you cannot fetch it, reply exactly with the single word FETCH_FAILED." \
--dangerously-skip-permissions --output-format json
```

Output: `{"conversation_id":"…","status":"SUCCESS","response":"# Page title…"}`

### Canonical `acquire(url)` (verified this session)
```python
def acquire(url: str) -> str:
    try:
        r = subprocess.run(
            [AGY_BIN, "-p",
             f"Fetch {url} and return ONLY the clean markdown body text, nothing else. "
             f"If you cannot fetch it, reply exactly with the single word FETCH_FAILED.",
             "--dangerously-skip-permissions", "--output-format", "json"],
            capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise RuntimeError(f"agy exit {r.returncode}: {r.stderr[:160]}")
        data = json.loads(r.stdout)
        if data.get("status") != "SUCCESS":
            raise RuntimeError(f"agy status {data.get('status')}")
        body = data.get("response", "").strip()
        if not body or "FETCH_FAILED" in body:
            raise RuntimeError("agy returned no content / FETCH_FAILED sentinel")
        return _normalize(body)
    except Exception as e:
        raise RuntimeError(f"acquire failed for {url}: {e}")
```

On any failure the function RAISES → the caller appends to `broken[]` and later
`alert_broken()` logs it. Garbage is never embedded.

## Notes
- `agy` version observed: 1.1.8. Binary at `/opt/homebrew/bin/agy` (macOS/homebrew).
- `--dangerously-skip-permissions` is required for non-interactive cron use.
- Latency: ~20s per URL via `agy` (includes agent init). Parallelize with
  `ThreadPoolExecutor(max_workers=6)` across sources; embed serially after.
- If `agy` is unavailable, Firecrawl REST (`POST https://api.firecrawl.dev/v1/scrape`
  with `FIRECRAWL_API_KEY`) is the deterministic equivalent. Regex scrape is last-resort
  only (noisy nav/footer leakage).
- Do NOT reintroduce `hermes chat` as the acquirer — it reintroduces the silent-garbage
  bug.
