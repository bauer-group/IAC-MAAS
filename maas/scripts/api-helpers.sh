#!/usr/bin/env bash
# =============================================================================
# MAAS API Helpers – Source: source maas/scripts/api-helpers.sh
# =============================================================================
P="${MAAS_PROFILE:-admin}"

maas_list_ready()    { maas $P machines read | jq -r '.[] | select(.status_name=="Ready") | "\(.system_id)\t\(.hostname)\t\(.cpu_count)C/\(.memory)M\t\(.tag_names|join(","))"' | column -t; }
maas_list_deployed() { maas $P machines read | jq -r '.[] | select(.status_name=="Deployed") | "\(.system_id)\t\(.hostname)\t\(.ip_addresses|join(","))\t\(.tag_names|join(","))"' | column -t; }
maas_list_by_tag()   { maas $P machines read | jq -r ".[] | select(.tag_names[]==\"$1\") | \"\(.system_id)\t\(.hostname)\t\(.status_name)\t\(.ip_addresses|join(\",\"))\"" | column -t; }
maas_status()        { maas $P machine read "$1" | jq '{hostname,status_name,power_state,cpu_count,memory,tag_names,ip_addresses}'; }
maas_power_on()      { maas $P machine power-on "$1"; }
maas_power_off()     { maas $P machine power-off "$1"; }

maas_bulk_deploy() {
  local TAG="$1" RELEASE="${2:-noble}"
  local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "Deploying all Ready machines with tag: ${TAG} (${RELEASE})"
  maas $P machines read | \
    jq -r ".[] | select(.status_name==\"Ready\") | select(.tag_names[]==\"${TAG}\") | .system_id" | \
    while read SID; do
      bash "${SCRIPT_DIR}/deploy-machine.sh" "${SID}" "${RELEASE}" <<< "y"
      sleep 5
    done
}

maas_summary() {
  echo "=== MAAS Cluster ==="
  echo "Status:"
  maas $P machines read | jq -r '[.[].status_name] | group_by(.) | .[] | "  \(.[0]): \(length)"'
  echo "Tags:"
  maas $P tags read | jq -r '.[] | "  \(.name): \(.machine_count // 0)"'
}

echo "Helpers loaded: maas_list_ready, maas_list_deployed, maas_list_by_tag <tag>"
echo "  maas_status <sid>, maas_bulk_deploy <tag> [release], maas_summary"
