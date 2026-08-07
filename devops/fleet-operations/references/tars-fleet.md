# TARS Fleet — Live Inventory (2026-08-07)

Operational snapshot for the fleet-operations skill. Update when nodes/roles/IPs change.

## Nodes

| Node | Tailscale IP | OS | Hardware | Role | SSH |
|---|---|---|---|---|---|
| Air M1 | 100.79.3.6 | macOS 26.5.1 | M1 8c, 8GB, 228GB (75% used, 51GB free) | Control/orquestacion (Hermes, 6 perfiles, MCPs, web factory CLIs, RAG ingest/UI) | local |
| Mini M4 | 100.90.88.5 | macOS 26.5.2 | M4 10c, 16GB, 228GB SSD (11%) + 3 externos | Cerebro 24/7 (Qdrant, EXO, n8n, Prometheus+Grafana, KG, hub backups, Hermes gateway) | `ssh macmini` (user quiquebs) |
| GEEKOM | 100.123.17.12 | Fedora 44 | Ryzen 9 7940HS 8c/16t, 16GB DDR5, 952GB NVMe (8%), Radeon 780M, **+ HDD 2TB TOSHIBA MQ01ABB200 (sda, sin formato, sin montar — pendiente mkfs)** | Computo + seguridad (Ollama 0.0.0.0:11434, Wazuh, lab pentest, Kali VM, pipeline nocturno) | `ssh root@100.123.17.12` (tailnet policy: SOLO root) |
| VPS Hermes Cloud | 100.92.51.13 | Linux | 2GB, 6GB | Relay 24/7 (gateway, Telegram bridge) — **A CANCELAR** (migrar Telegram a local antes) | sin SSH |

## Mini externos
- `/Volumes/RESPALDO` 1.8TB (10% used, 1.7TB free) — restic hub
- `/Volumes/Workspace` 466GB (51% used, 231GB free)
- `/Volumes/Backups` 1.8TB (11% used, 1.4TB free) — TimeMachine (root:wheel, NO usar para restic)

## Mini services (launchd, NO docker — Docker/colima no esta corriendo)
- Qdrant :6333 (8 colecciones: agent_memory, bgw_knowledge, cyber_knowledge, hermes_brain, hermes_memories, kg_full, mem0migrations, rag_demo)
- EXO LLM-distributed :52415 (app, PID via launchd)
- n8n :5678 (launchd com.quiquebs.n8n, PID 2500)
- ollama-balancer :4000 (launchd, script ~/.hermes/scripts/ollama-balancer.py)
- Ollama :11434 (app, **localhost ONLY** — lsof confirma 127.0.0.1, no accesible desde fleet)
- Prometheus :9090 (3/3 targets UP: Air, Mini, GEEKOM node_exporter)
- Grafana :3000 (v11.4.0, database ok)
- Node Exporter :9100 (homebrew, UP en Prometheus)
- kg-3d-server (PID 2508)
- mem0-local-api (PID 2504)
- hermes-ops-dashboard (PID 2491)
- Hermes gateway (PID 1965)
- context-agent, orion-coordinator (loaded, no PID = dormant)
- **12 LaunchAgents NO cargados** (inertes, ver §LaunchAgents Inertes abajo)
- `pmset sleep=0` confirmado (no duerme)

## Mini LaunchAgents inertes (audit 2026-08-07)
NO cargados en launchd, solo archivos que ensucian el inventario:
`com.quiquebs.qdrant`, `com.n8n.agent`, `com.omni.morning-digest`, `com.quique.daily-orchestrator`, `com.quique.master-watchdog`, `com.quiquebs.anthropic-ollama-proxy`, `com.quiquebs.second-brain.backup`, `com.quiquebs.second-brain.curator`, `com.quiquebs.second-brain.restore-test`, `com.quiquebs.second-brain.versioning`
Candidatos a archivar a `~/Library/LaunchAgents/_archive/` (no borrar).

## GEEKOM services
- Docker: wazuh stack (manager Up 23h, indexer Up 41h, dashboard Up 41h), lab (DVWA, Juice Shop, WebGoat), beszel + agent
- systemd: ollama (active, 0.0.0.0:11434), node_exporter (active, UP)
- Ollama models: nomic-embed-text, all-minilm, qwen3:8b, llama3.1:8b, llama3.2:3b, qwen2.5:3b
- Kali VM: running via qemu (4GB RAM asignada) — contribuye a presion de memoria
- **OOM kill reciente**: systemd-oomd mato llama-server (6.1GB RSS) — serializar cargas
- Swap: 3.3GB/8GB usado
- Wazuh agent host (ID 001): **inactive (dead), disabled** — systemd desactivado
- firewalld: 9100/tcp abierto (node_exporter)

## RAG corpus (audit 2026-08-07)
| Coleccion | Puntos | Nota |
|---|---|---|
| bgw_knowledge | 3,293 | 49 fuentes, 49/49 done en state file |
| cyber_knowledge | 6,111 | 40 fuentes, 40/40 done en state file (Elastic +243 entro) |
| hermes_brain | 1 | BLOQUEADO — Ollama Mini no persistente, indexer no puede llenar |
| agent_memory | existe | sin conteo |
| hermes_memories | existe | sin conteo |
| kg_full | existe | sin conteo |
| rag_demo | existe | no tocar |
| mem0migrations | existe | sin conteo |

## Wazuh SIEM (audit 2026-08-07)
| Agent ID | Nombre | Estado |
|---|---|---|
| 000 | wazuh.manager (server) | Active/Local |
| 001 | fedora (GEEKOM host) | Disconnected (systemd disabled) |
| 002 | QBS-MacAir-7 (Air) | Active |
| 005 | Mac-mini-de-Enrique (Mini) | Active |

## Backups restic (audit 2026-08-07)
| Repo | Snapshots | Ultimo | Tamano |
|---|---|---|---|
| air | 1 | 2026-08-05 21:53 | 7.4 GiB |
| mini | 1 | 2026-08-05 22:41 | 5.2 GiB |
| geekom | 2 | 2026-08-06 12:25 | 3.9 GiB |
**Gap de 2 dias sin backups nuevos.** Schedules existen pero no han corrido. Mini restic en `/opt/homebrew/bin/restic` (no en PATH de SSH).

## Schedules (operacional)
- Air: launchd 02:00 `ai.bokken.daily-backup` → `~/scripts/restic-backup-air.sh`; watchdog `disk-watchdog` (cada hora, hermes cron)
- Mini: cron 02:30 `restic-backup-mini.sh`; cron 03:00 `index_second_brain.py` (segundo cerebro → hermes_brain)
- GEEKOM: systemd timer 03:30 `pentest-nightly`; cron 06:00 `restic-backup-geekom.sh`

## Retirados (NO reintroducir)
- **Codex** (2026-08-05): cask purgado, ~/.codex a Trash
- **OpenClaw** (2026-08-05): gateway Mini parado y disabled, ~/.openclaw + npm pkg a Trash (~4.1G)
- **EXO**: marcado retirado antes, pero EXO app sigue corriendo en Mini :52415 (PID 2627) — verificar si debe limpiarse
- **n8n**: antes parado, ahora corriendo (PID 2500) sin workflows de negocio
- **Claude Code / proxy anthropic-to-ollama**: retirados

## Hechos del operador (evitar repeticion)
- **Bokken NO es de Quique** — es trabajo de web/paid media para clientes externos.
- Objetivos: trabajo remoto ciberseguridad (AI red teamer) + servicios web/paid media. Espanol para clientes, ingles para codigo.
- Filosofia Uncle Bob (SRP/DRY/SOLID) obligatoria para auditorias y arquitectura.
- Regla 6/8: diagnostico antes de editar; no editar a ciegas.
- "cada que arreglamos algo danamos algo mas" — verificar entre fixes, no apilar edits ciegos.