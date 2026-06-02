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

  namespace = "omniflow-staging"
  labels = {
    Environment = "staging"
    Project     = "omniflow"
  }
}

module "frontend" {
  source = "../../modules/frontend"

  namespace         = module.namespace.namespace_name
  image_tag         = "staging"
  replicas          = 2
  image_repository  = "ghcr.io/nkwatambe/omniflow-k8s-devops"

  config = {
    NODE_ENV               = "staging"
    VITE_APP_TITLE         = "OmniFlow Staging"
    NGINX_WORKER_PROCESSES = "auto"
    NGINX_WORKER_CONNECTIONS = "1024"
  }

  resources_requests_cpu    = "50m"
  resources_requests_memory = "64Mi"
  resources_limits_cpu      = "200m"
  resources_limits_memory   = "128Mi"

  hpa_enabled       = true
  hpa_min_replicas  = 2
  hpa_max_replicas  = 5
  hpa_target_cpu    = 70
  hpa_target_memory = 80

  topology_spread_enabled = true

  labels = {
    Environment = "staging"
    Project     = "omniflow"
  }
}

module "ingress" {
  source = "../../modules/ingress"

  namespace    = module.namespace.namespace_name
  service_name = module.frontend.service_name
  host         = "omniflow.staging.local"

  labels = {
    Environment = "staging"
    Project     = "omniflow"
  }
}
