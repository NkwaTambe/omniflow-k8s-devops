variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "omniflow-frontend"
}

variable "service_name" {
  description = "Service name to route traffic to"
  type        = string
}

variable "host" {
  description = "Host for the ingress rule"
  type        = string
}

variable "ingress_class" {
  description = "Ingress class name"
  type        = string
  default     = "nginx"
}

variable "tls_enabled" {
  description = "Enable TLS"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations"
  type        = map(string)
  default     = {}
}
