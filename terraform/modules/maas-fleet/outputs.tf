# =============================================================================
# MAAS Fleet Module – Outputs
# =============================================================================

output "hostnames" {
  description = "Hostnamen aller deployten Maschinen"
  value       = [for i in maas_instance.fleet : i.deploy_params[0].hostname]
}

output "ip_addresses" {
  description = "IP-Adressen aller deployten Maschinen"
  value       = [for i in maas_instance.fleet : i.ip_addresses]
}

output "instance_count" {
  description = "Anzahl deployter Maschinen"
  value       = length(maas_instance.fleet)
}
