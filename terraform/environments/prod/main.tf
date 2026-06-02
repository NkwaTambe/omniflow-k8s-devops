terraform {
  required_version = ">= 1.5.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

module "namespace" {
  source = "../../modules/namespace"

  namespace = "omniflow-prod"
  labels = {
    Environment = "prod"
    Project     = "omniflow"
  }
}

module "frontend" {
  source = "../../modules/frontend"

  namespace         = module.namespace.namespace_name
  image_tag         = "latest"
  replicas          = 3
  image_repository  = "ghcr.io/nkwatambe/omniflow-k8s-devops"

  config = {
    NODE_ENV               = "production"
    VITE_APP_TITLE         = "OmniFlow"
    NGINX_WORKER_PROCESSES = "auto"
    NGINX_WORKER_CONNECTIONS = "1024"
  }

  resources_requests_cpu    = "100m"
  resources_requests_memory = "128Mi"
  resources_limits_cpu      = "500m"
  resources_limits_memory   = "256Mi"

  hpa_enabled       = true
  hpa_min_replicas  = 3
  hpa_max_replicas  = 10
  hpa_target_cpu    = 70
  hpa_target_memory = 80

  topology_spread_enabled = true

  labels = {
    Environment = "prod"
    Project     = "omniflow"
  }
}

module "ingress" {
  source = "../../modules/ingress"

  namespace    = module.namespace.namespace_name
  service_name = module.frontend.service_name
  host         = "omniflow.example.com"

  annotations = {
    "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
  }

  labels = {
    Environment = "prod"
    Project     = "omniflow"
  }
}

module "monitoring" {
  source = "../../modules/monitoring"

  retention     = "30d"
  storage_size  = "50Gi"

  prometheus_cpu_request    = "500m"
  prometheus_memory_request = "2Gi"
  grafana_cpu_request       = "200m"
  grafana_memory_request    = "256Mi"
}
