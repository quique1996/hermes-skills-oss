# RAG verification recipe (run BEFORE declaring done)

Never claim a RAG system works on a plan. Exercise it. Minimal sequence:

## 1. Embedder alive + dims
```bash
curl -s http://OLLAMA:11434/api/embeddings -H 'Content-Type: application/json' \
  -d '{"model":"nomic-embed-text","prompt":"x"}' | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['embedding']))"
# expect 768
```

## 2. Qdrant collection exists + count
```bash
curl -s -X POST http://QDRANT:6333/collections/NAME/points/count \
  -H 'Content-Type: application/json' -d '{"exact":true}'
# expect {"result":{"count":N},"status":"ok"}
```

## 3. Roundtrip (embed → upsert → search back)
```python
import requests
text = "canary phrase unique to this test"
vec = requests.post(f"{OLAMA}/api/embeddings",
    json={"model":"nomic-embed-text","prompt":text}).json()["embedding"]
requests.put(f"{QDRANT}/collections/NAME/points?wait=true",
    json={"points":[{"id":999999,"vector":vec,"payload":{"text":text,"source":"smoke"}}]})
res = requests.post(f"{QDRANT}/collections/NAME/points/search",
    json={"vector":vec,"limit":1,"with_payload":True}).json()["result"]
assert res[0]["score"] > 0.99 and res[0]["payload"]["source"] == "smoke"
# cleanup
requests.post(f"{QDRANT}/collections/NAME/points/delete",
    json={"points":[999999]})
```

## 4. Retrieve for a real query
Embed the real question, search, print top-k sources. Confirm the returned chunks
are topically correct (e.g. "Godot WebGPU" returns the Godot Web Export doc, not noise).

## 5. End-to-end (with LLM)
Run the ask script with the real key. Assert the answer cites the corpus fact
(e.g. "WebGL 2.0" present, "WebGPU" discussed) and returncode == 0.

## Liveness note
If ping fails but `curl :6333/collections/.../count` works, the host blocks ICMP —
TCP is the real probe.
