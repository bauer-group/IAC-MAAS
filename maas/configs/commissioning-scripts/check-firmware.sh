#!/bin/bash
# --- Start MAAS 1.0 script metadata ---
# name: 99-check-firmware
# title: Check Firmware Versions
# description: Prüft BIOS, BMC, Disk und NIC Firmware
# script_type: commissioning
# timeout: 120
# --- End MAAS 1.0 script metadata ---

echo "═══ Firmware Check ═══"
echo "BIOS: $(dmidecode -s bios-version 2>/dev/null || echo 'N/A')"
echo "BMC:  $(ipmitool mc info 2>/dev/null | grep 'Firmware Revision' | awk '{print $NF}' || echo 'N/A')"
echo "Disks:"
lsblk -d -o NAME,MODEL,REV 2>/dev/null | tail -n +2
echo "NICs:"
for nic in /sys/class/net/*/device; do
  DEV=$(basename $(dirname "$nic"))
  FW=$(ethtool -i "$DEV" 2>/dev/null | grep firmware-version | awk '{print $2}')
  echo "  ${DEV}: ${FW:-N/A}"
done
