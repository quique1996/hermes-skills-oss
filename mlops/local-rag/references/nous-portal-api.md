# Nous Portal API — correct endpoint (verified 2026-08-06)

## The trap
`api.nousresearch.com` does NOT resolve (DNS / NameResolutionError, HTTPS 443).
Code using it fails with:
```
urllib3.exceptions.NameResolutionError: Failed to resolve 'api.nousresearch.com'
```

## Correct base
OpenAI-compatible. Use:
```
https://inference-api.nousresearch.com/v1
```
Chat completions path: `POST https://inference-api.nousresearch.com/v1/chat/completions`

## Auth
`Authorization: Bearer <NOUS_API_KEY>` where key prefix is `sk-nous-...`.
The key is loaded from a local `.env` (gitignored, chmod 600), never inline.

## Model
User-selected: `tencent/hy3:free` for the BGW tutor. Other valid Nous models exist
(e.g. `Hermes-4-405B`); confirm the exact slug against the portal before assuming.

## Minimal probe
```bash
curl -s https://inference-api.nousresearch.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $NOUS_API_KEY" \
  -d '{"model":"tencent/hy3:free","messages":[{"role":"user","content":"ping"}]}'
```
A non-DNS error (auth/quota) means the endpoint is right and only the key/slug is off.
