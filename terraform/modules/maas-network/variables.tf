# =============================================================================
# MAAS Network Module – Variables
# Alle Werte haben Defaults passend zu config.env
# =============================================================================

variable "fabric_name" {
  description = "Name der MAAS Fabric"
  type        = string
  default     = "bauer-group"
}

# ── PROVISION VLAN ──────────────────────────────────────────────────────────

variable "provision_vlan_vid" {
  description = "VLAN ID für Provisioning (PXE/DHCP)"
  type        = number
  default     = 100
}

variable "provision_vlan_name" {
  description = "VLAN Name"
  type        = string
  default     = "provision"
}

variable "provision_cidr" {
  description = "Provision Subnet CIDR"
  type        = string
  default     = "10.100.0.0/16"
}

variable "provision_gateway" {
  description = "Provision Subnet Gateway (MAAS Server)"
  type        = string
  default     = "10.100.0.1"
}

variable "provision_dhcp_start" {
  description = "DHCP Range Start"
  type        = string
  default     = "10.100.1.1"
}

variable "provision_dhcp_end" {
  description = "DHCP Range End"
  type        = string
  default     = "10.100.255.250"
}

variable "provision_dns_servers" {
  description = "DNS Server für Provision Subnet"
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

# ── MANAGEMENT VLAN ─────────────────────────────────────────────────────────

variable "mgmt_vlan_vid" {
  description = "VLAN ID für Management (SSH, Ansible, Monitoring)"
  type        = number
  default     = 110
}

variable "mgmt_vlan_name" {
  description = "VLAN Name"
  type        = string
  default     = "mgmt"
}

variable "mgmt_cidr" {
  description = "Management Subnet CIDR"
  type        = string
  default     = "10.110.0.0/16"
}

variable "mgmt_gateway" {
  description = "Management Subnet Gateway"
  type        = string
  default     = "10.110.0.1"
}

# ── BMC VLAN ────────────────────────────────────────────────────────────────

variable "bmc_vlan_vid" {
  description = "VLAN ID für BMC/IPMI"
  type        = number
  default     = 120
}

variable "bmc_vlan_name" {
  description = "VLAN Name"
  type        = string
  default     = "bmc"
}

variable "bmc_cidr" {
  description = "BMC Subnet CIDR"
  type        = string
  default     = "10.120.0.0/16"
}

variable "bmc_gateway" {
  description = "BMC Subnet Gateway (leer = kein Gateway)"
  type        = string
  default     = ""
}
