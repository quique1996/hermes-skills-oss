#!/bin/bash
# verify_changes.sh — Ad-hoc verification skeleton (fleet-operations skill).
# Copy to /private/var/folders/.../T/hermes-verify-<topic>.sh, fill the checks, run, then rm.
# Report the output as "Verification (ad-hoc, targeted — NOT suite green)".
set -u
FAIL=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAIL=1; }

echo "== 1. Sintaxis / integridad =="
bash -n /path/to/script.sh && ok "bash -n" || bad "bash -n"
plutil -lint /path/to/file.plist 2>/dev/null | grep -q OK && ok "plist valido" || bad "plist invalido"
python3 -m json.tool /path/to/config.json >/dev/null 2>&1 && ok "json valido" || bad "json invalido"

echo "== 2. Contenido esperado =="
grep -q "expected-string" /path/to/file && ok "contenido X presente" || bad "contenido X"
grep -q "old/broken-ref" /path/to/file && bad "resto viejo" || ok "sin restos viejos"

echo "== 3. Estado en vivo =="
# e.g. launchctl list | grep -q "<label>" && ok "job cargado" || bad "job no cargado"
# e.g. curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://host:port/ ... expected code

echo "== 4. PITFALLS de verificacion =="
# - NUNCA:  grep -q X file && ok || bad   → OK.
# - NUNCA:  grep X file | head -1 || echo "fallback"  → el || se liga a head (exit 0), el fallback nunca dispara.
# - NUNCA:  chequear la existencia del propio temp script desde dentro (falso positivo).
# - Cuidado con self-match en ssh: ps aux | grep "[patron]" dentro de ssh '...' matchea el cmdline del shell remoto.

echo
if [ $FAIL -eq 0 ]; then echo "VERIFICACION AD-HOC: TODO OK"; else echo "VERIFICACION AD-HOC: HAY FALLOS"; fi
exit $FAIL
