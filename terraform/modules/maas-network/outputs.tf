# =============================================================================
# MAAS Network Module – Outputs
# =============================================================================

output "fabric_id" {
  description = "MAAS Fabric ID"
  value       = maas_fabric.main.id
}

output "fabric_name" {
  description = "MAAS Fabric Name"
  value       = maas_fabric.main.name
}

# ── VLAN IDs ────────────────────────────────────────────────────────────────

output "provision_vlan_id" {
  description = "Provision VLAN resource ID"
  value       = maas_vlan.provision.id
}

output "mgmt_vlan_id" {
  description = "Management VLAN resource ID"
  value       = maas_vlan.mgmt.id
}

output "bmc_vlan_id" {
  description = "BMC VLAN resource ID"
  value       = maas_vlan.bmc.id
}

# ── Subnet IDs ──────────────────────────────────────────────────────────────

output "provision_subnet_id" {
  description = "Provision Subnet resource ID"
  value       = maas_subnet.provision.id
}

output "mgmt_subnet_id" {
  description = "Management Subnet resource ID"
  value       = maas_subnet.mgmt.id
}

output "bmc_subnet_id" {
  description = "BMC Subnet resource ID"
  value       = maas_subnet.bmc.id
}
