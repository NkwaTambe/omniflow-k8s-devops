output "ingress_name" {
  description = "Ingress resource name"
  value       = kubernetes_ingress_v1.frontend.metadata[0].name
}

output "ingress_host" {
  description = "Ingress host"
  value       = var.host
}
