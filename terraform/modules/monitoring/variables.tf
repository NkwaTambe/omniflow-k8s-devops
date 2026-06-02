variable "prometheus_stack_version" {
  description = "kube-prometheus-stack chart version"
  type        = string
  default     = "58.0.0"
}

variable "retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "10d"
}

variable "storage_size" {
  description = "Prometheus PVC size"
  type        = string
  default     = "10Gi"
}

variable "prometheus_cpu_request" {
  description = "Prometheus CPU request"
  type        = string
  default     = "200m"
}

variable "prometheus_memory_request" {
  description = "Prometheus memory request"
  type        = string
  default     = "512Mi"
}

variable "grafana_cpu_request" {
  description = "Grafana CPU request"
  type        = string
  default     = "100m"
}

variable "grafana_memory_request" {
  description = "Grafana memory request"
  type        = string
  default     = "128Mi"
}
