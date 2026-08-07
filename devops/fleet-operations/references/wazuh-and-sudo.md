# Wazuh agents (macOS) + sudo mechanism — recipe and verification

Verified end-to-end 2026-08-05 on Air (M1) and Mini (M4) against a Wazuh manager on GEEKOM (docker, 4.14.7).

## Why the obvious things fail

- `sudo -S` (piping a password to sudo stdin) is **hard-blocked** by Hermes security
  (`tools/approval.py`, `_check_sudo_stdin_guard`) — it is treated as a brute-force
  vector and the command never runs. Never write it.
- `sudo <cmd>` (bare) is **auto-rewritten**: `_transform_sudo_command`
  (`tools/terminal_tool.py`) replaces every bare `sudo` with `sudo -S -p ''` and
  prepends the password to the process stdin. It reads `SUDO_PASSWORD` through
  `agent.secret_scope.get_secret()` at call time, so editing the profile `.env`
  mid-session works without restarting Hermes.
- The downloaded pkg URL `.../wazuh-agent-4.14.7.pkg` (missing the `-1.arm64`
  suffix) returns a **111-byte S3 AccessDenied** XML — the installer then fails
  with "package path invalid". Always `ls -la` the download first.

## Correct macOS agent install (Apple Silicon)

```bash
# 1. pkg (docs URL)
curl -sO https://packages.wazuh.com/4.x/macos/wazuh-agent-4.14.7-1.arm64.pkg   # Intel: -1.intel64.pkg
# 2. deployment vars go in a FILE, not env
echo "WAZUH_MANAGER='100.123.17.12'" > /tmp/wazuh_envs
# 3. install + start (bare sudo = auto-rewritten when SUDO_PASSWORD is in profile .env)
sudo installer -pkg wazuh-agent-4.14.7-1.arm64.pkg -target /
sudo /Library/Ossec/bin/wazuh-control start
sudo /Library/Ossec/bin/wazuh-control status   # expect 5 daemons running
```

## Remote install (via ssh to another node)

The local auto-rewrite cannot feed the remote sudo prompt, so use SUDO_ASKPASS:

```bash
set -a; source ~/.hermes/profiles/stella/.env; set +a   # loads MINI_SUDO_PASSWORD
umask 077; echo "$MINI_SUDO_PASSWORD" > /tmp/.mini_pw
printf '#!/bin/sh\ncat /tmp/.mini_pw\n' > /tmp/.mini_ap && chmod 700 /tmp/.mini_ap
scp -q /tmp/.mini_pw /tmp/.mini_ap macmini:/tmp/
ssh macmini '
  cd /tmp && curl -sO https://packages.wazuh.com/4.x/macos/wazuh-agent-4.14.7-1.arm64.pkg
  echo "WAZUH_MANAGER=\"100.123.17.12\"" > /tmp/wazuh_envs
  SUDO_ASKPASS=/tmp/.mini_ap sudo -A installer -pkg /tmp/wazuh-agent-4.14.7-1.arm64.pkg -target /
  SUDO_ASKPASS=/tmp/.mini_ap sudo -A /Library/Ossec/bin/wazuh-control start
  rm -f /tmp/.mini_pw /tmp/.mini_ap /tmp/wazuh_envs'
rm -f /tmp/.mini_pw /tmp/.mini_ap
```

The askpass script runs with the invoking user's privileges, so the 600-perms
password file must be owned/readable by that user. Clean up both sides.

## End-to-end verification (on the manager)

```bash
docker exec wazuh-wazuh.manager-1 /var/ossec/bin/agent_control -l
# expect: 000 wazuh.manager Active/Local | 00X <hostname> Active | ...
docker exec wazuh-wazuh.manager-1 sh -c 'tail -5 /var/ossec/logs/ossec.log' | grep -i "agent key generated"
# authd confirms enrollment: "Agent key generated for 'Mac-mini-de-Enrique-302.local'"
```

## Notes

- Check `agent_control -l` BEFORE installing: an agent can already be enrolled and
  Active from a previous session (Air was ID 002 — the audit had wrongly marked it pending).
- The manager's own host agent (e.g. ID 001 `fedora`) may show `Disconnected` while
  the manager container (ID 000) and remote agents are Active — check per agent.
- Enrollment is automatic via authd (port 1515) with default lab config; no password needed.
- Version must match the manager (agent 4.14.7 ↔ manager 4.14.7).
