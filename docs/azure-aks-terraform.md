# Azure Test Deployment

This repo now contains a minimal Azure test deployment path using Terraform and AKS.

For a step-by-step explanation of how values flow from Terraform into Kubernetes manifests, see [docs/deployment-description.md](docs/deployment-description.md).

## What gets created

- Resource group
- Azure Container Registry
- AKS cluster
- Azure Service Bus namespace, topics, and subscriptions
- Azure SQL Server and application databases
- Azure Key Vault for Service Bus and SQL connection string secrets

## Files

- `infra/terraform/main.tf`
- `infra/terraform/main.tfvars.json`
- `infra/terraform/outputs.tf`
- `k8s/namespace.yaml`
- `k8s/secretproviderclass.yaml`
- `k8s/applications.yaml`
- `scripts/build-and-push.ps1`
- `scripts/deploy-aks.ps1`

## Deployment flow

1. Build and push container images.
2. Apply Terraform.
3. Fetch AKS credentials.
4. Render the Kubernetes manifests with Terraform outputs.
5. Apply the manifests.

## Commands

```powershell
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform apply -auto-approve -var-file=main.tfvars.json
```

```powershell
./scripts/build-and-push.ps1 -AcrName <acr-name>
./scripts/deploy-aks.ps1
```

## Notes

- This is a basic test environment, not a production design.
- Set `sql_admin_password` in `infra/terraform/main.tfvars.json` before first deploy.
- SQL connection strings and Service Bus connection string are pulled from Key Vault into Kubernetes using Secrets Store CSI.
- `webclient` is exposed through a public LoadBalancer service.