# =============================================================================
# IAC-MAAS – Production Environment
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers { maas = { source = "canonical/maas", version = "~> 2.0" } }
}

provider "maas" {
  api_version = "2.0"
  api_key     = var.maas_api_key
  api_url     = var.maas_api_url
}

variable "maas_api_url" { type = string; default = "http://10.110.0.1:5240/MAAS" }
variable "maas_api_key" { type = string; sensitive = true }

locals {
  ci_base = filebase64("${path.module}/../../cloud-init/templates/base.yaml")
}

# ── Netzwerk (Fabric, VLANs, Subnets, DHCP) ────────────────────────────────

module "network" {
  source = "../../modules/maas-network"
  # Defaults aus variables.tf passen zu config.env.
  # Überschreiben nur bei Abweichung:
  # provision_cidr = "10.100.0.0/16"
  # mgmt_cidr      = "10.110.0.0/16"
}

# ── Tags (Rollen + Hardware Auto-Tags) ──────────────────────────────────────

module "tags" {
  source = "../../modules/maas-tags"
  # Zusätzliche Tags:
  # additional_tags = {
  #   "database" = "Dedizierte Datenbank-Server"
  # }
}

# ── Einzelmaschine per System-ID ────────────────────────────────────────────
# System IDs nach Commissioning aus MAAS lesen:
#   maas admin machines read | jq '.[] | {hostname, system_id}'
#
# module "k8s_control_01" {
#   source    = "../../modules/maas-machine"
#   hostname  = "k8s-ctrl-01"
#   system_id = "abc123"
#   user_data = local.ci_base
# }

# ── Fleet-Deployment (N Maschinen nach Constraints) ─────────────────────────
#
# module "k8s_workers" {
#   source          = "../../modules/maas-fleet"
#   instance_count  = 5
#   hostname_prefix = "k8s-work"
#   tags            = ["k8s-worker"]
#   min_cpu_count   = 8
#   min_memory      = 16384
#   distro_series   = "noble"
#   user_data       = local.ci_base
# }
#
# module "monitoring" {
#   source          = "../../modules/maas-fleet"
#   instance_count  = 1
#   hostname_prefix = "mon"
#   tags            = ["monitoring"]
#   min_cpu_count   = 4
#   min_memory      = 8192
#   distro_series   = "noble"
#   user_data       = local.ci_base
# }
