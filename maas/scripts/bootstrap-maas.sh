#!/usr/bin/env bash
# =============================================================================
# MAAS Bootstrap – Installiert und konfiguriert MAAS Region+Rack Controller
# Repo: IAC-MAAS
# =============================================================================
set -euo pipefail

# ── Konfiguration laden ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.env"

[[ -f "${CONFIG_FILE}" ]] || { echo "ERROR: config.env nicht gefunden: ${CONFIG_FILE}"; exit 1; }
source "${CONFIG_FILE}"

# Variablen-Mapping
MAAS_ADMIN_EMAIL="${BAUER_ADMIN_EMAIL}"
MAAS_DOMAIN="${BAUER_DOMAIN}"
GITHUB_SSH_IMPORT="${BAUER_GITHUB_USER}"
UPSTREAM_DNS="${DNS_SERVERS}"

# Produktion: Eigene PostgreSQL verwenden statt maas-test-db
USE_EXTERNAL_DB=false
# DB_URI="postgres://maas:PASSWORD@db.internal/maasdb"

# ── Prüfungen ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "ERROR: Root erforderlich."; exit 1; }
command -v snap &>/dev/null || { echo "ERROR: snapd fehlt."; exit 1; }

echo "═══════════════════════════════════════════"
echo "  MAAS Bootstrap – $(date +%Y-%m-%d)"
echo "═══════════════════════════════════════════"

# ── 1. System ─────────────────────────────────────────────────────────────
echo "[1/8] System aktualisieren..."
apt-get update -qq && apt-get upgrade -y -qq

# ── 2. MAAS installieren ─────────────────────────────────────────────────
echo "[2/8] MAAS installieren (${MAAS_CHANNEL})..."
snap install maas --channel="${MAAS_CHANNEL}"

if [[ "${USE_EXTERNAL_DB}" == "false" ]]; then
  snap install maas-test-db
  sleep 10
  until sudo maas-test-db.psql -c "SELECT 1" &>/dev/null; do sleep 2; done
  DB_URI="maas-test-db:///"
fi

# ── 3. Initialisieren ────────────────────────────────────────────────────
echo "[3/8] MAAS initialisieren..."
maas init region+rack --database-uri "${DB_URI}"

# ── 4. Admin-User ────────────────────────────────────────────────────────
echo "[4/8] Admin-User erstellen..."
read -rsp "Admin-Passwort: " MAAS_ADMIN_PASS; echo
maas createadmin \
  --username "${MAAS_ADMIN_USER}" \
  --password "${MAAS_ADMIN_PASS}" \
  --email "${MAAS_ADMIN_EMAIL}" \
  --ssh-import "${GITHUB_SSH_IMPORT}"

# ── 5. API Key ────────────────────────────────────────────────────────────
echo "[5/8] API Key sichern..."
API_KEY=$(maas apikey --username "${MAAS_ADMIN_USER}")
mkdir -p /root/.maas && echo "${API_KEY}" > /root/.maas/api-key && chmod 600 /root/.maas/api-key

# ── 6. CLI Login ──────────────────────────────────────────────────────────
echo "[6/8] CLI Login..."
MAAS_URL="http://$(hostname -I | awk '{print $1}'):5240/MAAS/api/2.0/"
maas login "${MAAS_ADMIN_USER}" "${MAAS_URL}" "${API_KEY}"

# ── 7. Basiskonfiguration ────────────────────────────────────────────────
echo "[7/8] Basiskonfiguration..."
P="${MAAS_ADMIN_USER}"
maas $P maas set-config name=upstream_dns value="${UPSTREAM_DNS}"
maas $P maas set-config name=dnssec_validation value=no
maas $P maas set-config name=ntp_servers value="${NTP_SERVERS}"
maas $P maas set-config name=ntp_external_only value=false
maas $P maas set-config name=default_osystem value=ubuntu
maas $P maas set-config name=default_distro_series value=jammy
maas $P maas set-config name=commissioning_distro_series value=jammy
maas $P domains create name="${MAAS_DOMAIN}" 2>/dev/null || true

# ── 8. Boot Images ───────────────────────────────────────────────────────
echo "[8/8] Boot Images importieren..."
maas $P boot-source-selections create 1 os=ubuntu release=jammy arches=amd64 subarches='*' labels='*'
maas $P boot-source-selections create 1 os=ubuntu release=noble arches=amd64 subarches='*' labels='*'
maas $P boot-resources import

echo ""
echo "═══════════════════════════════════════════"
echo "  MAAS Bootstrap ABGESCHLOSSEN"
echo "═══════════════════════════════════════════"
echo "  Web UI:  http://$(hostname -I | awk '{print $1}'):5240/MAAS/"
echo "  API Key: /root/.maas/api-key"
echo ""
echo "  Nächster Schritt:"
echo "    bash maas/scripts/configure-network.sh"
echo "═══════════════════════════════════════════"
