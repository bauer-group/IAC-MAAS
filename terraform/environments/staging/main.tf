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

# Staging: Gleiche Struktur wie Production
# module "staging_01" {
#   source = "../../modules/maas-machine"
#   hostname = "staging-01"
#   system_id = "xyz789"
# }
