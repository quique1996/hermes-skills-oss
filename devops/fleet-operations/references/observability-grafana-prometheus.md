# Observability stack — Grafana + Prometheus + node_exporter (fleet)

Deployed 2026-08-05 on Mini (decision: Grafana over n8n for the Mini direction).
Prometheus :9090, Grafana :3000, node_exporter :9100 on Air/Mini/GEEKOM.

## Layout

- Stack dir on Mini: `~/grafana-stack/` (docker-compose.yml + prometheus.yml; survives reboots — do NOT keep in /tmp).
- Compose: prometheus `prom/prometheus:v3.3.0` + grafana `grafana/grafana:11.4.0`, both `restart: unless-stopped`, **named volumes** (`prometheus-data`, `grafana-data`).
- prometheus.yml scrapes `100.79.3.6:9100`, `100.90.88.5:9100`, `100.123.17.12:9100` (interval 30s).

## node_exporter install per OS

- macOS (Air/Mini): `brew install node_exporter && brew services start node_exporter` → :9100 immediately.
- Fedora (GEEKOM): download tarball (`node_exporter-1.9.1.linux-amd64.tar.gz`), `cp node_exporter /usr/local/bin/`, systemd unit `ExecStart=/usr/local/bin/node_exporter`, `Restart=always`, `systemctl enable --now`.

## The three traps (each cost real debugging time)

1. **Docker Desktop single-file bind mount fails**: `./prometheus.yml:/etc/prometheus/prometheus.yml:ro` errors "not a directory: Are you trying to mount a directory onto a file". Bind the whole DIRECTORY instead (mount the stack dir at `/etc/prometheus` — the image's default config path resolves) or use named volumes. Single-file binds from host /tmp are the worst case.

2. **External-volume binds break container uids**: binding `/Volumes/Workspace/grafana/...` as the data dir → prometheus panics in `promql.NewActiveQueryTracker` (uid 10001 can't write the query log) and grafana dies with "GF_PATHS_DATA='/var/lib/grafana' is not writable" (uid 472). chown'ing the macOS host dir to 10001/472 is fragile (noowners volume, Docker Desktop translation). Fix: named volumes — data lives in the Docker VM, which is fine for metrics after the CloudStorage removal freed the internal disk.

3. **Fedora SELinux + firewalld for node_exporter**:
   - `systemctl status` → `status=203/EXEC` with the binary present = SELinux context problem. Tar-extracted binaries land as `system_u:object_r:tmp_t:s0`. Fix: `restorecon -v /usr/local/bin/node_exporter` (→ `bin_t`). Check with `ls -Z`.
   - `firewall-cmd --add-port=9100/tcp` on the DEFAULT zone is not enough: tailscale0 is in the `trusted` zone, ethernet in `FedoraWorkstation`. Add to every active zone: `for z in $(firewall-cmd --get-active-zones | grep -v ":"); do firewall-cmd --permanent --zone=$z --add-port=9100/tcp; done; firewall-cmd --reload`.

## Verification (end-to-end)

```bash
curl -s :9090/api/v1/targets | python3 -c "import sys,json; [print(t['labels']['instance'], t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"
# expect 3/3 "up" (wait ≥1 scrape interval after a fix — 30s)
curl -s :3000/api/health   # {"database":"ok","version":"11.4.0"}
curl -s -o /dev/null -w "%{http_code}" :3000/login   # 200
```

Targets can stay `down` for one scrape cycle after a fix — re-check after 30-60s, not immediately.

## Grafana access

`http://100.90.88.5:3000` — admin/admin (change on first login). Data source: Prometheus at `http://grafana-prometheus:9090` (in-container DNS) or `http://100.90.88.5:9090` from the browser.

## Related decisions made same session

- Telegram: root config `platforms.telegram.enabled: true`; gateway reload requires the USER to run the restart from a separate shell (blocked from inside the session); 409 conflict with the VPS bot until the VPS is cancelled.
- Profile inventory: `hermes profile list` (singular) — 3 profiles (default/bokken/stella); bokken SOUL replaced (client-facing persona).
