# Source verification (pre-ingest curation)

Before a URL ever reaches the acquire→embed→upsert path, verify it is reachable
and durable. A broken or link-rot-prone source wastes an ingest slot and pollutes
the corpus. This is the step that runs *before* `references/acquisition-agy.md`.

## Canonical reachability check

Always verify with curl, not a Python HTTP client:

```bash
for u in "${urls[@]}"; do
  code=$(curl -sI -L --max-time 15 -o /dev/null -w "%{http_code}" "$u")
  echo "$code  $u"
done
```

- `200` = good. `301/302/308` that `-L` follows to `200` = good (resolve prior to recording).
- Reject `404`, `403`, `000` (timeout), and anything else.
- For an automated check, wrap the loop in a script that asserts every code is in
  `{200,301,302,308}` and fails nonzero on the first miss. Run it as an ad-hoc
  verifier after editing the source list (see `references/verification-recipe.md`).

## PITFALL: urllib 406 false-negative

`urllib.request` (default UA + Accept headers) gets **HTTP 406 Not Acceptable**
from some hosts that serve `200` to curl/browsers — e.g. `learnopengl.com`.
A Python `HEAD`/`GET` 406 is NOT proof the URL is dead. If a link "fails" under
urllib, re-check with `curl -sI -L` (optionally `-A "Mozilla/5.0 ..."`) before
discarding it. Prefer curl as the canonical verifier for the whole curation step.

## Source-quality rules

- Prefer official docs, stable spec URLs, and active GitHub repo *roots or solid
  doc pages* over `raw.githubusercontent.com` file paths (raw files 404 when a
  branch/tag is moved or the file is renamed).
- Avoid single-blog / forum pages prone to link rot; prefer canonical references.
- For a curated list deliverable, return a Python tuple list
  `NAME_URLS = [("Name", "https://..."), ...]` and verify each entry with the
  curl loop above before handing it off.

## Domain gotchas observed (BGW: Blender/Godot/WebGPU/web-3D corpus)

- **Godot GDExtension docs moved.** In current stable docs
  `tutorials/scripting/gdextension/index.html` → **404**. The C++/GDExtension
  content now lives under `tutorials/scripting/cpp/index.html`. When a Godot docs
  path 404s, list the parent directory via the GitHub API
  (`api.github.com/repos/godotengine/godot-docs/contents/<dir>`) to find the new
  file name instead of guessing.
- **Khronos wiki blocks bots.** `khronos.org/opengl/wiki/...` returns `403` to
  automated clients. Use the glTF *registry* spec
  (`registry.khronos.org/glTF/specs/2.0/glTF-2.0.html`), MDN WebGL, or LearnOpenGL
  as GLSL/OpenGL references instead.
- **WGSL spec** is stable at `https://www.w3.org/TR/WGSL/`.
- **Three.js** general docs (`threejs.org/docs/`) vs the WebGPURenderer manual
  page are distinct URLs — don't treat them as duplicates.
