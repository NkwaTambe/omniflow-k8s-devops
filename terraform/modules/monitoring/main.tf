terraform {
  required_version = ">= 1.5.0"
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

resource "helm_release" "prometheus_stack" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = var.prometheus_stack_version

  values = [
    templatefile("${path.module}/values/prometheus-stack.yaml.tpl", {
      retention = var.retention
      storage_size = var.storage_size
    })
  ]

  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = var.prometheus_cpu_request
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = var.prometheus_memory_request
  }

  set {
    name  = "grafana.resources.requests.cpu"
    value = var.grafana_cpu_request
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = var.grafana_memory_request
  }
}
