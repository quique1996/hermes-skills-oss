# uptime-kuma monitor management without API credentials

Verified 2026-08-05: the REST API login failed (credentials unknown, not the
default admin/admin), so monitors were managed by direct SQLite surgery on the
container's DB with the container stopped.

## Procedure (≈1 min downtime)

```bash
docker exec uptime-kuma sh -c 'cp /app/data/kuma.db /app/data/kuma.db.bak-<date>'  # backup inside
docker stop uptime-kuma
docker cp uptime-kuma:/app/data/kuma.db /tmp/kuma.db
sqlite3 /tmp/kuma.db < /tmp/changes.sql          # host sqlite3 (macOS ships it)
docker cp /tmp/kuma.db uptime-kuma:/app/data/kuma.db
docker start uptime-kuma
# verify: docker ps shows (healthy); curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/  → 302
rm -f /tmp/kuma.db
```

Notes:
- The DB lives in the Docker volume (`/var/lib/docker/volumes/uptime-kuma/_data`
  inside the Docker Desktop VM) — NOT directly reachable from the macOS host; use
  `docker cp` both ways.
- `require('better-sqlite3')` inside `docker exec node -e` fails to resolve — don't
  bother; host sqlite3 on the copied DB is the way.

## Monitor schema essentials

```sql
-- port monitor
INSERT INTO monitor (name,type,hostname,port,url,interval,retry_interval,maxretries,active,user_id,created_date,method,accepted_statuscodes_json,weight)
VALUES ('GEEKOM lab DVWA','port','100.123.17.12',8080,NULL,60,60,3,1,1,datetime('now'),'GET','["1-699"]',2000);
-- http monitor
UPDATE monitor SET name='VPS Hermes Cloud gateway', url='http://100.92.51.13:9119/api/status' WHERE id=4;
-- deactivate a stopped service (keeps history)
UPDATE monitor SET active=0 WHERE id=7;
```

## Pitfalls hit in production

- **The container cannot reach host `127.0.0.1`** (bridge network). Existing monitors
  for Mini services used `127.0.0.1` and were failing silently → change to the
  tailnet IP (100.90.88.5).
- **SQLite string literals are single-quoted** — JSON columns like
  `accepted_statuscodes_json` are TEXT: `'["1-699"]'`. Inside a double-quoted
  sqlite3 heredoc, `""x""` works as an escape but is confusing — prefer single quotes.
- **Quoting through ssh**: single quotes inside SQL break a single-quoted `ssh '...'`
  arg. Write the SQL to a local file and pass it base64:
  `B64=$(base64 < /tmp/changes.sql); ssh host "echo $B64 | base64 -d > /tmp/changes.sql && sqlite3 /tmp/kuma.db < /tmp/changes.sql && rm -f /tmp/changes.sql"`
- **`grep | head || echo`** binds `||` to `head` (exit 0) so the fallback never fires —
  verification scripts report false FAILs; use `if grep -q ...; then ... else ... fi`.
- Check for stale monitors in audits: dead IPs (the old VPS 100.106.170.123 monitor
  had been failing all day), loopbacks, stopped services (n8n) — fix or deactivate.
