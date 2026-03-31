# Deployment Description (Easy Guide)

This document explains the full Azure deployment flow in simple terms:

1. How Azure resource names and IDs are created.
2. Where values are saved.
3. How those values get into Kubernetes YAML.
4. How the app reads them at runtime.
5. How to deploy without PowerShell scripts.

## 1) How Azure resource names and IDs are generated

Terraform creates resources from [infra/terraform/main.tf](infra/terraform/main.tf).

Resource names are generated with Azure CAF naming resources like:

- `azurecaf_name.resource_group`
- `azurecaf_name.aks`
- `azurecaf_name.acr`
- `azurecaf_name.key_vault`
- `azurecaf_name.servicebus`
- `azurecaf_name.sql_server`

After Terraform creates each resource, Azure assigns:

- A full Azure Resource ID (ARM ID), for example:
  - `/subscriptions/.../resourceGroups/.../providers/Microsoft.ContainerRegistry/registries/...`
- Service-specific values, for example:
  - ACR login server
  - AKS cluster name
  - Key Vault name
  - SQL server FQDN

You do not manually compute these IDs. Terraform obtains them directly from Azure responses.

## 2) Where values are saved

There are two storage layers:

1. Terraform state (`terraform.tfstate`):
   - Stores all created resource metadata, including IDs and attributes.
2. Terraform outputs in [infra/terraform/outputs.tf](infra/terraform/outputs.tf):
   - Exposes selected values in a convenient way for scripts.

Important outputs used by deployment:

- `resource_group_name`
- `aks_cluster_name`
- `acr_login_server`
- `key_vault_name`
- `key_vault_secret_provider_client_id`

The deployment script reads these with:

```powershell
terraform output -raw <output_name>
```

## 3) How values get into YAML files

Template YAML files contain placeholders:

- [k8s/secretproviderclass.yaml](k8s/secretproviderclass.yaml)
  - `__KV_PROVIDER_CLIENT_ID__`
  - `__KEY_VAULT_NAME__`
  - `__TENANT_ID__`
- [k8s/applications.yaml](k8s/applications.yaml)
  - `__ACR_LOGIN_SERVER__`

The script [scripts/deploy-aks.ps1](scripts/deploy-aks.ps1) does string replacement:

1. Reads Terraform outputs.
2. Replaces placeholders in the template files.
3. Writes rendered files:
   - `k8s/secretproviderclass.rendered.yaml`
   - `k8s/applications.rendered.yaml`
4. Applies rendered files with `kubectl apply`.

This is why the YAML files can stay generic and still work in different environments.

## 4) How secrets and connection strings are read by pods

The flow is:

1. Terraform creates Key Vault secrets:
   - Service Bus connection string
   - SQL connection strings per service database
2. AKS has Key Vault CSI provider enabled.
3. `SecretProviderClass` tells AKS which Key Vault and which secret names to read.
4. CSI syncs these into Kubernetes secret `sb-secrets`.
5. Deployments read env vars from `sb-secrets` using `valueFrom.secretKeyRef`.

Example from [k8s/applications.yaml](k8s/applications.yaml):

- `ConnectionStrings__DefaultConnection` from `EventCatalogConnectionString`
- `ServiceBusConnectionString` from `ServiceBusConnectionString`

In ASP.NET Core, env vars with `__` map to config sections (`:`), so:

- `ConnectionStrings__DefaultConnection` becomes `ConnectionStrings:DefaultConnection`

That is what your services read via `IConfiguration`.

## 5) What is using Azure Resource IDs directly

You mostly do not reference full ARM IDs in YAML. Terraform uses ARM IDs internally to connect resources.

Examples in [infra/terraform/main.tf](infra/terraform/main.tf):

- Role assignments use `scope = <resource>.id`.
- Service Bus topics/subscriptions use `namespace_id` and `topic_id`.
- Databases use `server_id`.

For Kubernetes, you pass friendly values (names, FQDN, client IDs, login server) via outputs and rendered YAML.

## 6) Deployment steps (current PS1 path)

1. Build and push images to ACR:

```powershell
./scripts/build-and-push.ps1 -AcrName <acr-name>
```

2. Deploy infrastructure and apps:

```powershell
./scripts/deploy-aks.ps1
```

## 7) Alternative ways (without PS1)

### Option A: Manual CLI commands

You can run the same flow manually:

1. `terraform -chdir=infra/terraform init`
2. `terraform -chdir=infra/terraform validate`
3. `terraform -chdir=infra/terraform apply -auto-approve -var-file=main.tfvars.json`
4. `az aks get-credentials --resource-group <rg> --name <aks> --overwrite-existing`
5. Replace placeholders in YAML using your preferred tool.
6. `kubectl apply -f ...`

### Option B: Bash script

Create a `.sh` script that does the same replacements with `sed`/`envsubst` and calls Terraform + kubectl.

### Option C: CI/CD pipeline

Use GitHub Actions or Azure DevOps:

1. Terraform plan/apply stage.
2. Build/push images stage.
3. Render YAML from templates stage.
4. AKS deploy stage.

This is better for repeatability and team usage.

## 8) Troubleshooting checklist

1. Verify Terraform outputs:

```powershell
terraform -chdir=infra/terraform output
```

2. Verify rendered placeholders are gone:

```powershell
Select-String -Path k8s/*.rendered.yaml -Pattern "__"
```

3. Verify SecretProviderClass and synced secret:

```powershell
kubectl get secretproviderclass -n globoticket
kubectl get secret sb-secrets -n globoticket -o yaml
```

4. Verify deployment env is wired:

```powershell
kubectl describe pod -n globoticket <pod-name>
```

5. Verify app logs:

```powershell
kubectl logs -n globoticket <pod-name>
```
