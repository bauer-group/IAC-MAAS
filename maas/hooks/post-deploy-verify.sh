#!/usr/bin/env bash
# Post-Deploy Verify: SSH + cloud-init + node-identity + ansible-pull
set -euo pipefail
P="admin"; SID="${1:?Usage: $0 <SYSTEM_ID>}"

HOSTNAME=$(maas $P machine read "$SID" | jq -r '.hostname')
IP=$(maas $P machine read "$SID" | jq -r '.ip_addresses[0]')
echo "═══ Post-Deploy Verify: ${HOSTNAME} (${IP}) ═══"

# SSH Wait
echo "[1/4] SSH..."
for i in $(seq 1 30); do
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "ubuntu@${IP}" "echo ok" 2>/dev/null && break
  sleep 10
done

# cloud-init
echo "[2/4] cloud-init..."
ssh -o StrictHostKeyChecking=accept-new "ubuntu@${IP}" "sudo cloud-init status --format json" 2>/dev/null | jq .

# Node Identity
echo "[3/4] Node Identity..."
ssh -o StrictHostKeyChecking=accept-new "ubuntu@${IP}" "cat /etc/bauer-group/node-identity.json" 2>/dev/null | jq .

# Ansible Pull Timer
echo "[4/4] Ansible Pull Timer..."
ssh -o StrictHostKeyChecking=accept-new "ubuntu@${IP}" "systemctl is-active ansible-pull.timer" 2>/dev/null

echo ""
echo "═══ Verify OK: ssh ubuntu@${IP} ═══"
