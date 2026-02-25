# =============================================================================
# MAAS Tags Module – Rollen-Tags + Hardware Auto-Tags
#
# Rollen-Tags werden manuell zugewiesen (kein XPath).
# Hardware-Tags nutzen XPath-Definitionen und werden von MAAS automatisch
# nach dem Commissioning auf passende Maschinen angewendet.
# =============================================================================

terraform {
  required_providers {
    maas = { source = "canonical/maas", version = "~> 2.0" }
  }
}

# ── Rollen-Tags (manuelle Zuweisung) ───────────────────────────────────────

resource "maas_tag" "k8s_control" {
  name    = "k8s-control"
  comment = "Kubernetes Control Plane Node"
}

resource "maas_tag" "k8s_worker" {
  name    = "k8s-worker"
  comment = "Kubernetes Worker Node"
}

resource "maas_tag" "monitoring" {
  name    = "monitoring"
  comment = "Monitoring Stack (Prometheus, Grafana, Loki)"
}

resource "maas_tag" "storage" {
  name    = "storage"
  comment = "Storage Node (Ceph, Longhorn)"
}

resource "maas_tag" "docker" {
  name    = "docker"
  comment = "Docker Standalone Host"
}

# ── Hardware Auto-Tags (XPath, automatische Zuweisung) ─────────────────────
#
# MAAS wertet diese XPath-Ausdrücke gegen die lshw-XML-Daten aus,
# die während des Commissionings gesammelt werden.

resource "maas_tag" "gpu_nvidia" {
  name       = "gpu-nvidia"
  comment    = "Auto: NVIDIA GPU erkannt"
  definition = "//node[@class='display']/vendor[contains(.,'NVIDIA')]"
}

resource "maas_tag" "nvme" {
  name       = "nvme"
  comment    = "Auto: NVMe Storage erkannt"
  definition = "//node[@class='disk']/description[contains(.,'NVMe')]"
}

resource "maas_tag" "ssd" {
  name       = "ssd"
  comment    = "Auto: SSD Storage erkannt"
  definition = "//node[@class='disk']/capabilities/capability[@id='ssd']"
}

resource "maas_tag" "high_cpu" {
  name       = "high-cpu"
  comment    = "Auto: 32+ CPU Kerne"
  definition = "//node[@id='cpu' and @width='64']//setting[@id='cores' and number(@value)>=32]"
}

resource "maas_tag" "high_memory" {
  name       = "high-memory"
  comment    = "Auto: 64GB+ RAM"
  definition = "//node[@id='memory']/size[number(.)>=68719476736]"
}

resource "maas_tag" "dual_nic" {
  name       = "dual-nic"
  comment    = "Auto: 2+ Netzwerk-Interfaces"
  definition = "//node[@class='network' and position()=2]"
}

# ── Benutzerdefinierte Tags ─────────────────────────────────────────────────

resource "maas_tag" "additional" {
  for_each = var.additional_tags

  name    = each.key
  comment = each.value
}
