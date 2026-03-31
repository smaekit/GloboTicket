output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_secret_provider_client_id" {
  value = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].client_id
}

output "service_bus_namespace" {
  value = azurerm_servicebus_namespace.servicebus.name
}

output "service_bus_connection_secret_name" {
  value = azurerm_key_vault_secret.servicebus_connection_string.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.sql.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "github_client_id" {
  value       = azuread_application.github_oidc.client_id
  description = "Set this as the AZURE_CLIENT_ID secret in your GitHub repository"
}