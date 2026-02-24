#!/usr/bin/env bash
set -euo pipefail
P="admin"
echo "Boot Images importieren..."
maas $P boot-resources import
echo "Warte auf Abschluss (erster Import: 10-30 Min)..."
while maas $P boot-resources is-importing | jq -re '. == true' &>/dev/null; do
  printf "." ; sleep 15
done
echo ""
echo "Verfügbare Images:"
maas $P boot-resources read | jq -r '.[] | "  \(.name) [\(.architecture)]"'
