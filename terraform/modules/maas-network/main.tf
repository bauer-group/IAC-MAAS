# =============================================================================
# MAAS Network Module – Fabric, VLANs, Subnets
#
# Deklarative Netzwerk-Konfiguration für MAAS.
# Ersetzt die imperativen Aufrufe in configure-network.sh.
# =============================================================================

terraform {
  required_providers {
    maas = { source = "canonical/maas", version = "~> 2.0" }
  }
}

# ── Fabric ──────────────────────────────────────────────────────────────────

resource "maas_fabric" "main" {
  name = var.fabric_name
}

# ── VLANs ───────────────────────────────────────────────────────────────────

resource "maas_vlan" "provision" {
  fabric = maas_fabric.main.id
  vid    = var.provision_vlan_vid
  name   = var.provision_vlan_name
}

resource "maas_vlan" "mgmt" {
  fabric = maas_fabric.main.id
  vid    = var.mgmt_vlan_vid
  name   = var.mgmt_vlan_name
}

resource "maas_vlan" "bmc" {
  fabric = maas_fabric.main.id
  vid    = var.bmc_vlan_vid
  name   = var.bmc_vlan_name
}

# ── Subnets ─────────────────────────────────────────────────────────────────

resource "maas_subnet" "provision" {
  cidr       = var.provision_cidr
  fabric     = maas_fabric.main.id
  vlan       = maas_vlan.provision.vid
  gateway_ip = var.provision_gateway
  dns_servers = var.provision_dns_servers

  ip_ranges {
    type     = "dynamic"
    start_ip = var.provision_dhcp_start
    end_ip   = var.provision_dhcp_end
    comment  = "MAAS DHCP for PXE provisioning"
  }

  ip_ranges {
    type     = "reserved"
    start_ip = cidrhost(var.provision_cidr, 1)
    end_ip   = cidrhost(var.provision_cidr, 99)
    comment  = "Infrastructure reserved"
  }
}

resource "maas_subnet" "mgmt" {
  cidr       = var.mgmt_cidr
  fabric     = maas_fabric.main.id
  vlan       = maas_vlan.mgmt.vid
  gateway_ip = var.mgmt_gateway
  dns_servers = var.provision_dns_servers
}

resource "maas_subnet" "bmc" {
  cidr   = var.bmc_cidr
  fabric = maas_fabric.main.id
  vlan   = maas_vlan.bmc.vid

  gateway_ip = var.bmc_gateway != "" ? var.bmc_gateway : null
}
