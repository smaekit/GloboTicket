terraform {
  required_version = ">= 1.4.0"

  # Remote state stored in Azure Blob Storage.
  # The storage account must be created before running terraform init.
  # See docs/pipelines.md for the one-time setup commands.
  backend "azurerm" {
    resource_group_name  = "rg-globoticket-tfstate"
    storage_account_name = "stglobotickettfstate"
    container_name       = "tfstate"
    key                  = "globoticket.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "~> 1.2"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}


variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "location" {
  type = string
}

variable "environment" {
  type = string
}

variable "project_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "node_vm_size" {
  type = string
}

variable "node_count" {
  type = number
}

variable "sql_location" {
  type = string
}

variable "sql_admin_login" {
  type = string
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

variable "github_org" {
  type        = string
  description = "GitHub organization or username that owns the repository"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

data "azurerm_client_config" "current" {}

locals {
  tags = {
    Environment = var.environment
    Project     = var.project_name
    Workload    = "globoticket"
  }
}

resource "azurecaf_name" "resource_group" {
  name          = var.project_name
  resource_type = "azurerm_resource_group"
}

resource "azurecaf_name" "acr" {
  name          = var.project_name
  resource_type = "azurerm_container_registry"
}

resource "azurecaf_name" "aks" {
  name          = var.project_name
  resource_type = "azurerm_kubernetes_cluster"
}

resource "azurecaf_name" "servicebus" {
  name          = var.project_name
  resource_type = "azurerm_servicebus_namespace"
}

resource "azurecaf_name" "key_vault" {
  name          = var.project_name
  resource_type = "azurerm_key_vault"
}

resource "azurecaf_name" "sql_server" {
  name          = var.project_name
  resource_type = "azurerm_mssql_server"
}

resource "azurerm_resource_group" "rg" {
  name     = azurecaf_name.resource_group.result
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "acr" {
  name                = replace(azurecaf_name.acr.result, "-", "")
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_servicebus_namespace" "servicebus" {
  name                = azurecaf_name.servicebus.result
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  local_auth_enabled  = true
  tags                = local.tags
}

resource "azurerm_servicebus_namespace_authorization_rule" "apps" {
  name         = "apps"
  namespace_id = azurerm_servicebus_namespace.servicebus.id
  listen       = true
  send         = true
  manage       = false
}

resource "azurerm_servicebus_topic" "checkout" {
  name         = "checkoutmessage"
  namespace_id = azurerm_servicebus_namespace.servicebus.id
}

resource "azurerm_servicebus_topic" "payment_request" {
  name         = "orderpaymentrequestmessage"
  namespace_id = azurerm_servicebus_namespace.servicebus.id
}

resource "azurerm_servicebus_topic" "payment_updated" {
  name         = "orderpaymentupdatedmessage"
  namespace_id = azurerm_servicebus_namespace.servicebus.id
}

resource "azurerm_servicebus_subscription" "order_checkout" {
  name               = "globoticketorder"
  topic_id           = azurerm_servicebus_topic.checkout.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "payment_requests" {
  name               = "globoticketpayment"
  topic_id           = azurerm_servicebus_topic.payment_request.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "order_payment_updated" {
  name               = "globoticketorder"
  topic_id           = azurerm_servicebus_topic.payment_updated.id
  max_delivery_count = 10
}

resource "azurerm_key_vault" "kv" {
  name                          = azurecaf_name.key_vault.result
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  rbac_authorization_enabled    = true
  public_network_access_enabled = true
  tags                          = local.tags

  depends_on = [
    azurerm_role_assignment.github_owner
  ]
}

resource "azurerm_role_assignment" "current_user_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "github_oidc_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_service_principal.github_oidc.object_id
}

resource "azurerm_key_vault_secret" "servicebus_connection_string" {
  name         = "service-bus-connection-string"
  value        = azurerm_servicebus_namespace_authorization_rule.apps.primary_connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.current_user_key_vault_secrets_officer
  ]
}

resource "azurerm_mssql_server" "sql" {
  name                          = azurecaf_name.sql_server.result
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.sql_location
  version                       = "12.0"
  administrator_login           = var.sql_admin_login
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  tags                          = local.tags

  depends_on = [
    azurerm_role_assignment.github_owner
  ]
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "eventcatalog" {
  name      = "GloboTicketEventCatalogDb"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"
}

resource "azurerm_mssql_database" "shoppingbasket" {
  name      = "GloboTicketShoppingBasketDb"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"
}

resource "azurerm_mssql_database" "ordering" {
  name      = "GloboTicketOrderDb"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"
}

resource "azurerm_mssql_database" "discount" {
  name      = "GloboTicketDiscountDb"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"
}

resource "azurerm_mssql_database" "marketing" {
  name      = "GloboTicketMarketingDb"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"
}

locals {
  sql_server_name = azurerm_mssql_server.sql.fully_qualified_domain_name

  eventcatalog_connection_string = "Server=tcp:${local.sql_server_name},1433;Initial Catalog=${azurerm_mssql_database.eventcatalog.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  shoppingbasket_connection_string = "Server=tcp:${local.sql_server_name},1433;Initial Catalog=${azurerm_mssql_database.shoppingbasket.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  ordering_connection_string = "Server=tcp:${local.sql_server_name},1433;Initial Catalog=${azurerm_mssql_database.ordering.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  discount_connection_string = "Server=tcp:${local.sql_server_name},1433;Initial Catalog=${azurerm_mssql_database.discount.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  marketing_connection_string = "Server=tcp:${local.sql_server_name},1433;Initial Catalog=${azurerm_mssql_database.marketing.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};MultipleActiveResultSets=true;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

resource "azurerm_key_vault_secret" "eventcatalog_connection_string" {
  name         = "eventcatalog-db-conn"
  value        = local.eventcatalog_connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.current_user_key_vault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "shoppingbasket_connection_string" {
  name         = "shoppingbasket-db-conn"
  value        = local.shoppingbasket_connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.current_user_key_vault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "ordering_connection_string" {
  name         = "ordering-db-conn"
  value        = local.ordering_connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.current_user_key_vault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "discount_connection_string" {
  name         = "discount-db-conn"
  value        = local.discount_connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.current_user_key_vault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "marketing_connection_string" {
  name         = "marketing-db-conn"
  value        = local.marketing_connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.current_user_key_vault_secrets_officer
  ]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = azurecaf_name.aks.result
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.project_name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name            = "sys"
    node_count      = var.node_count
    vm_size         = var.node_vm_size
    os_disk_size_gb = 30
  }

  identity {
    type = "SystemAssigned"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  tags = local.tags

  depends_on = [
    azurerm_role_assignment.github_owner
  ]
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

resource "azurerm_role_assignment" "aks_key_vault_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].object_id

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

resource "azurerm_role_assignment" "aks_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].object_id

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC Identity
# ---------------------------------------------------------------------------
# Creates an App Registration + Service Principal that GitHub Actions can
# authenticate as using OIDC (no client secrets stored anywhere).
# First run: execute manually with `az login`. After that, use the pipelines.

resource "azuread_application" "github_oidc" {
  display_name = "${var.project_name}-github-actions"
}

resource "azuread_service_principal" "github_oidc" {
  client_id = azuread_application.github_oidc.client_id
}

resource "azuread_application_federated_identity_credential" "github_main" {
  application_id = azuread_application.github_oidc.id
  display_name   = "github-main"
  description    = "GitHub Actions OIDC trust for the main branch"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
  audiences      = ["api://AzureADTokenExchange"]
}

# Owner is required because this Terraform config itself creates role assignments
# (e.g. ACR Pull, Key Vault roles). For production, scope this down further.
resource "azurerm_role_assignment" "github_owner" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.github_oidc.object_id
}