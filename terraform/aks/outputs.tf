output "cluster_name" {
  value       = azurerm_kubernetes_cluster.main.name
  description = "Name of the AKS cluster"
}

output "cluster_endpoint" {
  value       = azurerm_kubernetes_cluster.main.fqdn
  description = "Fully qualified domain name of the AKS API server"
}