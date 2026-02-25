# =============================================================================
# MAAS Fleet Module – Variables
# =============================================================================

variable "instance_count" {
  description = "Anzahl der zu deployenden Maschinen"
  type        = number
}

variable "hostname_prefix" {
  description = "Hostname-Prefix (wird zu prefix-01, prefix-02, ...)"
  type        = string
}

variable "tags" {
  description = "Tags für die Maschinen-Allokation (müssen in MAAS existieren)"
  type        = list(string)
  default     = []
}

variable "min_cpu_count" {
  description = "Minimum CPU Kerne (0 = keine Einschränkung)"
  type        = number
  default     = 0
}

variable "min_memory" {
  description = "Minimum RAM in MB (0 = keine Einschränkung)"
  type        = number
  default     = 0
}

variable "zone" {
  description = "MAAS Zone (leer = beliebig)"
  type        = string
  default     = ""
}

variable "pool" {
  description = "MAAS Resource Pool (leer = default)"
  type        = string
  default     = ""
}

variable "distro_series" {
  description = "Ubuntu Release"
  type        = string
  default     = "noble"
}

variable "user_data" {
  description = "Base64-encoded cloud-init User Data"
  type        = string
  default     = ""
}
