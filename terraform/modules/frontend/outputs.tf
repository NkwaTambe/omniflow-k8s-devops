output "deployment_name" {
  description = "Deployment name"
  value       = kubernetes_deployment.frontend.metadata[0].name
}

output "service_name" {
  description = "Service name"
  value       = kubernetes_service.frontend.metadata[0].name
}

output "config_map_name" {
  description = "ConfigMap name"
  value       = kubernetes_config_map.frontend.metadata[0].name
}

output "namespace" {
  description = "Namespace"
  value       = var.namespace
}
