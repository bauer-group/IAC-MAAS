# =============================================================================
# MAAS Fleet Module – Count-based Deployment mit Hardware-Constraints
#
# Deployt N Maschinen mit automatischer Allokation basierend auf
# Tags, CPU/RAM Anforderungen und Zone.
#
# Verwendung:
#   module "k8s_workers" {
#     source          = "../../modules/maas-fleet"
#     instance_count  = 5
#     hostname_prefix = "k8s-work"
#     tags            = ["k8s-worker"]
#     min_cpu_count   = 8
#     min_memory      = 16384
#     distro_series   = "noble"
#     user_data       = local.ci_base
#   }
# =============================================================================

terraform {
  required_providers {
    maas = { source = "canonical/maas", version = "~> 2.0" }
  }
}

resource "maas_instance" "fleet" {
  count = var.instance_count

  allocate_params {
    hostname      = "${var.hostname_prefix}-${format("%02d", count.index + 1)}"
    tags          = length(var.tags) > 0 ? var.tags : null
    min_cpu_count = var.min_cpu_count > 0 ? var.min_cpu_count : null
    min_memory    = var.min_memory > 0 ? var.min_memory : null
    zone          = var.zone != "" ? var.zone : null
    pool          = var.pool != "" ? var.pool : null
  }

  deploy_params {
    distro_series = var.distro_series
    user_data     = var.user_data
  }
}
