output "prometheus_release_name" {
  description = "Helm release name for monitoring stack"
  value       = helm_release.prometheus_stack.name
}

output "grafana_namespace" {
  description = "Namespace where Grafana is deployed"
  value       = "monitoring"
}
