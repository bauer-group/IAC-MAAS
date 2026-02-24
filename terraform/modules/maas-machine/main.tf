terraform {
  required_providers {
    maas = { source = "canonical/maas", version = "~> 2.0" }
  }
}

variable "hostname"       { type = string }
variable "system_id"      { type = string }
variable "distro_series"  { type = string; default = "noble" }
variable "user_data"      { type = string; default = "" }

resource "maas_instance" "machine" {
  deploy_params {
    distro_series = var.distro_series
    user_data     = var.user_data
  }
  allocate_params {
    system_id = var.system_id
    hostname  = var.hostname
  }
}

output "hostname"     { value = var.hostname }
output "ip_addresses" { value = maas_instance.machine.ip_addresses }
