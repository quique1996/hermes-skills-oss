# Secure API-key handling for RAG ask-scripts

## Do NOT
- Paste the key into a shell command (it lands in shell history / process list).
- Commit `.env` to git.

## Do
1. `.gitignore` the secret file.
   ```
   .env
   *.env
   ```
2. Write via a `--set-key` CLI mode (not a pasted inline arg):
   ```python
   if args.set_key:
       p = Path(__file__).resolve().parent / ".env"
       lines = []
       if p.exists():
           lines = [l for l in p.read_text().splitlines() if not l.startswith("NOUS_API_KEY")]
       lines.append(f'NOUS_API_KEY="{args.set_key}"')
       p.write_text("\n".join(lines) + "\n")
       os.chmod(p, 0o600)
       return
   ```
3. Loader reads `.env` at import, sets `os.environ`, NEVER prints it:
   ```python
   _ENV = Path(__file__).resolve().parent / ".env"
   if _ENV.exists():
       for line in _ENV.read_text().splitlines():
           line = line.strip()
           if not line or line.startswith("#") or "=" not in line:
               continue
           k, v = line.split("=", 1)
           os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
   ```
4. Verify: key absent from any stdout; file perms `0600`; `git check-ignore .env` exits 0.

## Graceful failure
If the key is missing, raise a clear `RuntimeError("NOUS_API_KEY no definida")` caught
in `main()`; print the retrieved context to stderr and exit(2) — never a raw traceback.
