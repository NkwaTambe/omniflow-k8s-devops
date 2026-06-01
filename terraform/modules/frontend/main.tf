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

resource "kubernetes_config_map" "frontend" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = var.namespace
    labels = local.common_labels
  }

  data = var.config
}

resource "kubernetes_secret" "frontend" {
  count = length(var.secrets) > 0 ? 1 : 0

  metadata {
    name      = "${var.app_name}-secrets"
    namespace = var.namespace
    labels    = local.common_labels
  }

  data = var.secrets

  type = "Opaque"
}

resource "kubernetes_service_account" "frontend" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  automount_service_account_token = false
}

resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.selector_labels
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    template {
      metadata {
        labels = local.selector_labels
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "80"
          "prometheus.io/path"   = "/health"
          "checksum/config"      = sha256(jsonencode(var.config))
        }
      }

      spec {
        service_account_name            = kubernetes_service_account.frontend.metadata[0].name
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 1001
          run_as_group    = 1001
          fs_group        = 1001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        dynamic "topology_spread_constraint" {
          for_each = var.topology_spread_enabled ? [1] : []
          content {
            max_skew            = 1
            topology_key        = "kubernetes.io/hostname"
            when_unsatisfiable  = "DoNotSchedule"
            label_selector {
              match_labels = local.selector_labels
            }
          }
        }

        container {
          name  = var.app_name
          image = "${var.image_repository}:${var.image_tag}"

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.frontend.metadata[0].name
            }
          }

          resources {
            limits = {
              cpu    = var.resources_limits_cpu
              memory = var.resources_limits_memory
            }
            requests = {
              cpu    = var.resources_requests_cpu
              memory = var.resources_requests_memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 30
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 3
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          startup_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 0
            period_seconds        = 5
            failure_threshold     = 12
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp-nginx"
            mount_path = "/tmp"
          }

          volume_mount {
            name       = "var-cache-nginx"
            mount_path = "/var/cache/nginx"
          }

          volume_mount {
            name       = "var-run"
            mount_path = "/var/run"
          }
        }

        volume {
          name = "tmp-nginx"
          empty_dir {}
        }

        volume {
          name = "var-cache-nginx"
          empty_dir {}
        }

        volume {
          name = "var-run"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      protocol    = "TCP"
    }

    selector = local.selector_labels
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "frontend" {
  count = var.hpa_enabled ? 1 : 0

  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = var.app_name
    }

    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type               = "Utilization"
          average_utilization = var.hpa_target_cpu
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type               = "Utilization"
          average_utilization = var.hpa_target_memory
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 60
        select_policy                = "Max"
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type          = "Percent"
          value         = 10
          period_seconds = 60
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "frontend" {
  count = var.network_policy_enabled ? 1 : 0

  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    pod_selector {
      match_labels = local.selector_labels
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "app.kubernetes.io/part-of" = "omniflow-platform"
          }
        }
      }
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "ingress-nginx"
          }
        }
      }

      ports {
        port     = 80
        protocol = "TCP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            "app.kubernetes.io/name" = "kube-system"
          }
        }
      }

      ports {
        port     = 53
        protocol = "TCP"
      }
      ports {
        port     = 53
        protocol = "UDP"
      }
    }
  }
}

locals {
  common_labels = merge(var.labels, {
    "app.kubernetes.io/name"       = var.app_name
    "app.kubernetes.io/component"  = "frontend"
    "app.kubernetes.io/part-of"    = "omniflow-platform"
    "app.kubernetes.io/managed-by" = "terraform"
  })

  selector_labels = {
    "app.kubernetes.io/name"      = var.app_name
    "app.kubernetes.io/component" = "frontend"
  }
}
