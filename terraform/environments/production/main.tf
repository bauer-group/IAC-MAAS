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

# System IDs nach Commissioning aus MAAS lesen:
#   maas admin machines read | jq '.[] | {hostname, system_id}'
#
# module "k8s_worker_01" {
#   source = "../../modules/maas-machine"
#   hostname = "k8s-work-01"
#   system_id = "abc123"
#   user_data = local.ci_base
# }
