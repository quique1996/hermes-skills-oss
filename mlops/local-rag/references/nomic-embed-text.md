# nomic-embed-text — context limit & chunking (verified 2026-08-06)

## Fact
Ollama `nomic-embed-text` outputs **768-dim** vectors. It has a constrained context:
inputs beyond roughly 2048 tokens return HTTP 500:
```
{"error":"the input length exceeds the context length"}
```
(Confirmed empirically: ~1200 words OK, ~1600+ words 500s.)

## Rule
Chunk source text by **characters**, not words:
- size ≈ 1400 chars
- overlap ≈ 150 chars
This stays safely under the limit even for dense docs (e.g. Three.js WebGPU page
which yields 8000+ char HTML blobs).

## Why words fail
Word-based chunking (e.g. 600 words ≈ 800 tokens) can still overflow when a single
"word" chunk is actually a long concatenated HTML blob. Char windows are deterministic.

## Reference chunker (Python)
```python
def chunk(text, size=1400, overlap=150):
    if not text:
        return
    step = max(1, size - overlap)
    for i in range(0, len(text), step):
        yield text[i:i + size]
```

## Embedding call
```python
import requests
r = requests.post(f"{OLAMA}/api/embeddings",
                  json={"model":"nomic-embed-text","prompt":text}, timeout=60)
vec = r.json()["embedding"]   # len == 768
```

## vs all-minilm
`all-minilm` = 384 dims. Do NOT mix: a 384-d embedder cannot upsert into a 768-d
Qdrant collection. Standardize on `nomic-embed-text` (768) for quality + compatibility.
