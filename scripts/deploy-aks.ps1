param(
    [string]$TerraformFolder = "infra/terraform",
    [string]$K8sFolder = "k8s"
)

$ErrorActionPreference = "Stop"

Push-Location $TerraformFolder
terraform init
terraform validate
terraform apply -auto-approve -var-file="main.tfvars.json"

$resourceGroupName = terraform output -raw resource_group_name
$aksClusterName = terraform output -raw aks_cluster_name
$acrLoginServer = terraform output -raw acr_login_server
$keyVaultName = terraform output -raw key_vault_name
$kvProviderClientId = terraform output -raw key_vault_secret_provider_client_id
Pop-Location

az aks get-credentials --resource-group $resourceGroupName --name $aksClusterName --overwrite-existing

$secretProvider = Get-Content "$K8sFolder/secretproviderclass.yaml" -Raw
$secretProvider = $secretProvider.Replace("__KV_PROVIDER_CLIENT_ID__", $kvProviderClientId)
$secretProvider = $secretProvider.Replace("__KEY_VAULT_NAME__", $keyVaultName)
$secretProvider = $secretProvider.Replace("__TENANT_ID__", (az account show --query tenantId -o tsv))
$secretProvider | Set-Content "$K8sFolder/secretproviderclass.rendered.yaml"

$applications = Get-Content "$K8sFolder/applications.yaml" -Raw
$applications = $applications.Replace("__ACR_LOGIN_SERVER__", $acrLoginServer)
$applications | Set-Content "$K8sFolder/applications.rendered.yaml"

kubectl apply -f "$K8sFolder/namespace.yaml"
kubectl apply -f "$K8sFolder/secretproviderclass.rendered.yaml"
kubectl apply -f "$K8sFolder/applications.rendered.yaml"

kubectl get svc -n globoticket