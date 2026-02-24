#!/usr/bin/env bash
# =============================================================================
# MAAS Netzwerk-Konfiguration – VLANs, Subnets, DHCP
# =============================================================================
set -euo pipefail
P="${MAAS_ADMIN_USER:-admin}"

# ── Konfiguration laden ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.env"

[[ -f "${CONFIG_FILE}" ]] || { echo "ERROR: config.env nicht gefunden: ${CONFIG_FILE}"; exit 1; }
source "${CONFIG_FILE}"

FABRIC_NAME="main"

declare -A VLANS=( [provision]=${PROVISION_VLAN_ID} [mgmt]=${MGMT_VLAN_ID} [bmc]=${BMC_VLAN_ID} )
# Format: CIDR|GATEWAY|DNS
declare -A SUBNETS=(
  [provision]="${PROVISION_CIDR}|${PROVISION_GW}|${MGMT_GW}"
  [mgmt]="${MGMT_CIDR}|${MGMT_GW}|${MGMT_GW}"
  [bmc]="${BMC_CIDR}||"
)
DHCP_START="${PROVISION_DHCP_START}"
DHCP_END="${PROVISION_DHCP_END}"
DHCP_SUBNET="${PROVISION_CIDR}"

# ── Prüfung ──────────────────────────────────────────────────────────────
maas ${P} version read &>/dev/null || {
  echo "ERROR: MAAS CLI nicht eingeloggt."
  echo "  maas login admin http://<IP>:5240/MAAS/api/2.0/ \$(cat /root/.maas/api-key)"
  exit 1
}

echo "═══════════════════════════════════════════"
echo "  MAAS Netzwerk-Konfiguration"
echo "═══════════════════════════════════════════"

# ── Fabric ────────────────────────────────────────────────────────────────
FABRIC_ID=$(maas $P fabrics read | jq -r ".[] | select(.name==\"${FABRIC_NAME}\") | .id" 2>/dev/null)
if [[ -z "${FABRIC_ID}" || "${FABRIC_ID}" == "null" ]]; then
  FABRIC_ID=$(maas $P fabrics create name="${FABRIC_NAME}" | jq -r '.id')
  echo "[✓] Fabric '${FABRIC_NAME}' erstellt (ID=${FABRIC_ID})"
else
  echo "[·] Fabric '${FABRIC_NAME}' existiert (ID=${FABRIC_ID})"
fi

# ── VLANs ─────────────────────────────────────────────────────────────────
for NAME in "${!VLANS[@]}"; do
  VID="${VLANS[$NAME]}"
  EXISTS=$(maas $P vlans read "${FABRIC_ID}" | jq -r ".[] | select(.vid==${VID}) | .id" 2>/dev/null)
  if [[ -z "${EXISTS}" || "${EXISTS}" == "null" ]]; then
    maas $P vlans create "${FABRIC_ID}" vid="${VID}" name="${NAME}" > /dev/null
    echo "[✓] VLAN ${NAME} (VID ${VID}) erstellt"
  else
    echo "[·] VLAN ${NAME} (VID ${VID}) existiert"
  fi
done

# ── Subnets ───────────────────────────────────────────────────────────────
for NAME in "${!SUBNETS[@]}"; do
  IFS='|' read -r CIDR GW DNS <<< "${SUBNETS[$NAME]}"
  VID="${VLANS[$NAME]}"
  VLAN_ID=$(maas $P vlans read "${FABRIC_ID}" | jq -r ".[] | select(.vid==${VID}) | .id")
  EXISTS=$(maas $P subnets read | jq -r ".[] | select(.cidr==\"${CIDR}\") | .id" 2>/dev/null)
  if [[ -z "${EXISTS}" || "${EXISTS}" == "null" ]]; then
    CMD="maas $P subnets create cidr=${CIDR} vlan=${VLAN_ID}"
    [[ -n "${GW}" ]] && CMD+=" gateway_ip=${GW}"
    [[ -n "${DNS}" ]] && CMD+=" dns_servers=${DNS}"
    eval "${CMD}" > /dev/null
    echo "[✓] Subnet ${CIDR} (${NAME}) erstellt"
  else
    echo "[·] Subnet ${CIDR} (${NAME}) existiert"
  fi
done

# ── DHCP (nur PROVISION) ─────────────────────────────────────────────────
PROV_SUB=$(maas $P subnets read | jq -r ".[] | select(.cidr==\"${DHCP_SUBNET}\") | .id")
PROV_VLAN=$(maas $P vlans read "${FABRIC_ID}" | jq -r ".[] | select(.vid==${VLANS[provision]}) | .id")
RACK_ID=$(maas $P rack-controllers read | jq -r '.[0].system_id')

EXISTS=$(maas $P ipranges read | jq -r ".[] | select(.start_ip==\"${DHCP_START}\") | .id" 2>/dev/null)
if [[ -z "${EXISTS}" || "${EXISTS}" == "null" ]]; then
  maas $P ipranges create type=dynamic start_ip="${DHCP_START}" end_ip="${DHCP_END}" subnet="${PROV_SUB}" > /dev/null
  echo "[✓] DHCP Range ${DHCP_START}-${DHCP_END}"
fi

maas $P vlan update "${FABRIC_ID}" "${PROV_VLAN}" dhcp_on=true primary_rack="${RACK_ID}" > /dev/null
echo "[✓] DHCP aktiviert auf PROVISION VLAN"

# ── Tags erstellen ────────────────────────────────────────────────────────
echo ""
echo "Tags erstellen..."
for TAG in k8s-control k8s-worker monitoring storage docker gpu ssd; do
  maas $P tags create name="${TAG}" 2>/dev/null && echo "[✓] Tag: ${TAG}" || echo "[·] Tag: ${TAG} existiert"
done

# Auto-Detection Tags
maas $P tags create name=has-nvidia \
  definition='//node[@id="display"]/vendor[contains(text(),"NVIDIA")]' 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════"
echo "  Netzwerk-Konfiguration ABGESCHLOSSEN"
echo "═══════════════════════════════════════════"
