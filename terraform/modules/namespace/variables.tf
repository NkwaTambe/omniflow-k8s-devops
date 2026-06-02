variable "namespace" {
  description = "Kubernetes namespace name"
  type        = string
}

variable "labels" {
  description = "Additional labels for the namespace"
  type        = map(string)
  default     = {}
}
