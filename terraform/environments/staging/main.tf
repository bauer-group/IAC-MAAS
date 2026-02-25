# =============================================================================
# IAC-MAAS – Staging Environment
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

# ── Netzwerk (gleiche Struktur wie Production) ──────────────────────────────

module "network" {
  source = "../../modules/maas-network"
}

# ── Tags ────────────────────────────────────────────────────────────────────

module "tags" {
  source = "../../modules/maas-tags"
}

# ── Staging Maschinen ───────────────────────────────────────────────────────
#
# module "staging_fleet" {
#   source          = "../../modules/maas-fleet"
#   instance_count  = 2
#   hostname_prefix = "staging"
#   distro_series   = "noble"
#   user_data       = local.ci_base
# }
