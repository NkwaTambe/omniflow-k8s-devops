variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "omniflow-frontend"
}

variable "labels" {
  description = "Additional labels"
  type        = map(string)
  default     = {}
}

variable "image_repository" {
  description = "Container image repository"
  type        = string
  default     = "ghcr.io/nkwatambe/omniflow-k8s-devops"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "replicas" {
  description = "Number of deployment replicas"
  type        = number
  default     = 3
}

variable "config" {
  description = "ConfigMap data"
  type        = map(string)
  default = {
    NODE_ENV               = "production"
    VITE_APP_TITLE         = "OmniFlow"
    NGINX_WORKER_PROCESSES = "auto"
    NGINX_WORKER_CONNECTIONS = "1024"
  }
}

variable "secrets" {
  description = "Secret data (base64 values will be encoded by provider)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "resources_requests_cpu" {
  description = "CPU request"
  type        = string
  default     = "50m"
}

variable "resources_requests_memory" {
  description = "Memory request"
  type        = string
  default     = "64Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit"
  type        = string
  default     = "200m"
}

variable "resources_limits_memory" {
  description = "Memory limit"
  type        = string
  default     = "128Mi"
}

variable "hpa_enabled" {
  description = "Enable HorizontalPodAutoscaler"
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "HPA minimum replicas"
  type        = number
  default     = 3
}

variable "hpa_max_replicas" {
  description = "HPA maximum replicas"
  type        = number
  default     = 10
}

variable "hpa_target_cpu" {
  description = "HPA target CPU utilization percentage"
  type        = number
  default     = 70
}

variable "hpa_target_memory" {
  description = "HPA target memory utilization percentage"
  type        = number
  default     = 80
}

variable "topology_spread_enabled" {
  description = "Enable topology spread constraints"
  type        = bool
  default     = true
}

variable "network_policy_enabled" {
  description = "Enable NetworkPolicy"
  type        = bool
  default     = true
}

variable "wait_for_rollout" {
  description = "Wait for deployment rollout to complete before Terraform returns. Set false for local dev where image patching is needed."
  type        = bool
  default     = true
}
