#!/usr/bin/env bash
# =============================================================================
# Deploy Machine – Rendered cloud-init + MAAS Deploy
# Usage: deploy-machine.sh <SYSTEM_ID> [RELEASE]
#   RELEASE: jammy | noble (Default: noble)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.env"

[[ -f "${CONFIG_FILE}" ]] || { echo "ERROR: config.env nicht gefunden: ${CONFIG_FILE}"; exit 1; }
source "${CONFIG_FILE}"

P="${MAAS_ADMIN_USER:-admin}"
TPL_FILE="${REPO_ROOT}/cloud-init/templates/base.yaml"

# ── Args prüfen ──────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <SYSTEM_ID> [RELEASE]"
  echo ""
  echo "  RELEASE: jammy | noble (Default: noble)"
  echo ""
  echo "Ready Machines:"
  maas $P machines read 2>/dev/null | \
    jq -r '.[] | select(.status_name=="Ready") | "  \(.system_id)  \(.hostname)\t[\(.tag_names | join(", "))]"' | \
    column -t -s $'\t' || true
  exit 1
fi

SID="$1"
RELEASE="${2:-noble}"

[[ -f "${TPL_FILE}" ]] || { echo "ERROR: Template '${TPL_FILE}' nicht gefunden."; exit 1; }

# ── Maschine validieren ──────────────────────────────────────────────────
MACHINE_JSON=$(maas $P machine read "${SID}" 2>/dev/null) || { echo "ERROR: Maschine ${SID} nicht gefunden."; exit 1; }
STATUS=$(echo "${MACHINE_JSON}" | jq -r '.status_name')
HOSTNAME=$(echo "${MACHINE_JSON}" | jq -r '.hostname')
TAGS=$(echo "${MACHINE_JSON}" | jq -r '.tag_names | join(",")')

[[ "${STATUS}" == "Ready" ]] || {
  echo "ERROR: ${HOSTNAME} ist '${STATUS}', nicht 'Ready'."
  echo "  Falls 'Deployed': maas admin machine release ${SID}"
  exit 1
}

# ── Template rendern ─────────────────────────────────────────────────────
RENDERED=$(mktemp /tmp/cloud-init-XXXXXX.yaml)
trap "rm -f ${RENDERED}" EXIT

# Escape sed-spezifische Zeichen in Werten
escape_sed() { printf '%s\n' "$1" | sed 's/[&/\]/\\&/g'; }

sed \
  -e "s|##ANSIBLE_REPO_URL##|$(escape_sed "${ANSIBLE_REPO_URL}")|g" \
  -e "s|##ANSIBLE_REPO_BRANCH##|$(escape_sed "${ANSIBLE_REPO_BRANCH}")|g" \
  -e "s|##HOSTNAME##|$(escape_sed "${HOSTNAME}")|g" \
  -e "s|##MAAS_TAGS##|$(escape_sed "${TAGS}")|g" \
  -e "s|##TIMEZONE##|$(escape_sed "${BAUER_TIMEZONE}")|g" \
  -e "s|##BAUER_ORG##|$(escape_sed "${BAUER_ORG}")|g" \
  "${TPL_FILE}" > "${RENDERED}"

# ── Bestätigung ──────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo "  Deploy: ${HOSTNAME} (${SID})"
echo "  Release: ${RELEASE}"
echo "  Tags: ${TAGS}"
echo "  Ansible: ${ANSIBLE_REPO_URL} @ ${ANSIBLE_REPO_BRANCH}"
echo "═══════════════════════════════════════════"
read -p "Starten? [y/N] " -n 1 -r; echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "Abgebrochen."; exit 0; }

# ── Deploy ───────────────────────────────────────────────────────────────
USER_DATA=$(base64 -w0 "${RENDERED}")
maas $P machine deploy "${SID}" distro_series="${RELEASE}" user_data="${USER_DATA}"

echo ""
echo "Deployment gestartet: ${HOSTNAME}"
echo "  Status:  watch -n5 'maas admin machine read ${SID} | jq -r .status_name'"
echo "  Verify:  bash maas/hooks/post-deploy-verify.sh ${SID}"
