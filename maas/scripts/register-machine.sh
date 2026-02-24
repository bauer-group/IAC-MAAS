#!/usr/bin/env bash
# =============================================================================
# Neue Hardware in MAAS registrieren
# Usage: register-machine.sh --hostname X --bmc-ip X --bmc-user X --bmc-pass X [--tags X,Y]
# =============================================================================
set -euo pipefail
P="admin"

# ── Args parsen ──────────────────────────────────────────────────────────
HOSTNAME="" ; BMC_IP="" ; BMC_USER="admin" ; BMC_PASS="" ; TAGS="" ; POWER_TYPE="ipmi"

while [[ $# -gt 0 ]]; do
  case $1 in
    --hostname)   HOSTNAME="$2"; shift 2 ;;
    --bmc-ip)     BMC_IP="$2"; shift 2 ;;
    --bmc-user)   BMC_USER="$2"; shift 2 ;;
    --bmc-pass)   BMC_PASS="$2"; shift 2 ;;
    --tags)       TAGS="$2"; shift 2 ;;
    --power-type) POWER_TYPE="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

[[ -n "${HOSTNAME}" && -n "${BMC_IP}" && -n "${BMC_PASS}" ]] || {
  echo "Usage: $0 --hostname <name> --bmc-ip <ip> --bmc-user <user> --bmc-pass <pass> [--tags k8s-worker,ssd]"
  exit 1
}

# ── BMC Erreichbarkeit prüfen ─────────────────────────────────────────────
echo "BMC ${BMC_IP} prüfen..."
ping -c1 -W3 "${BMC_IP}" &>/dev/null || { echo "WARNING: BMC ${BMC_IP} nicht pingbar."; }

if command -v ipmitool &>/dev/null; then
  ipmitool -I lanplus -H "${BMC_IP}" -U "${BMC_USER}" -P "${BMC_PASS}" chassis status &>/dev/null && \
    echo "[✓] IPMI Verbindung OK" || echo "[!] IPMI Verbindung fehlgeschlagen"
fi

# ── In MAAS registrieren ─────────────────────────────────────────────────
echo "Maschine '${HOSTNAME}' registrieren..."
RESULT=$(maas $P machines create \
  hostname="${HOSTNAME}" \
  architecture=amd64/generic \
  power_type="${POWER_TYPE}" \
  power_parameters="{\"power_address\":\"${BMC_IP}\",\"power_user\":\"${BMC_USER}\",\"power_pass\":\"${BMC_PASS}\"}")

SID=$(echo "${RESULT}" | jq -r '.system_id')
echo "[✓] Registriert: ${HOSTNAME} (${SID})"

# ── Tags setzen ──────────────────────────────────────────────────────────
if [[ -n "${TAGS}" ]]; then
  IFS=',' read -ra TAG_ARRAY <<< "${TAGS}"
  for TAG in "${TAG_ARRAY[@]}"; do
    maas $P tags create name="${TAG}" 2>/dev/null || true
    maas $P tag update-nodes "${TAG}" add="${SID}" > /dev/null
    echo "[✓] Tag: ${TAG}"
  done
fi

# ── Commissioning starten ────────────────────────────────────────────────
echo "Commissioning starten..."
maas $P machine commission "${SID}" > /dev/null

echo ""
echo "═══════════════════════════════════════════"
echo "  ${HOSTNAME} registriert und Commissioning gestartet"
echo "  System ID: ${SID}"
echo "  Status:    watch -n10 'maas admin machine read ${SID} | jq -r .status_name'"
echo "═══════════════════════════════════════════"
