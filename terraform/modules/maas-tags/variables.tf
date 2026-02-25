# =============================================================================
# MAAS Tags Module – Variables
# =============================================================================

variable "additional_tags" {
  description = "Zusätzliche Tags (Name → Beschreibung)"
  type        = map(string)
  default     = {}
}
