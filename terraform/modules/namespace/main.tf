terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/part-of" = "omniflow-platform"
    })
  }
}
