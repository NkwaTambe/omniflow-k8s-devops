terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

resource "kubernetes_ingress_v1" "frontend" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"       = var.app_name
      "app.kubernetes.io/component"  = "frontend"
      "app.kubernetes.io/managed-by" = "terraform"
    })
    annotations = merge(var.annotations, {
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "10m"
    })
  }

  spec {
    ingress_class_name = var.ingress_class

    dynamic "tls" {
      for_each = var.tls_enabled ? [1] : []
      content {
        hosts       = [var.host]
        secret_name = "${var.app_name}-tls"
      }
    }

    rule {
      host = var.host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.service_name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
