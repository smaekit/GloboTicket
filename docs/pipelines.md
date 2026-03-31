# GitHub Actions Pipelines

This project has three GitHub Actions workflows that replace the local PowerShell scripts for managing infrastructure and deployments.

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Developer / GitHub UI                  │
└───────────────┬──────────────────────────────────────────┘
                │ Manual trigger (workflow_dispatch)
                ▼
┌──────────────────────────────────────────────────────────┐
│  1. terraform.yml  ──►  Azure Infrastructure             │
│     (apply/destroy)     AKS, ACR, SQL, Service Bus,      │
│                         Key Vault, App Registration       │
└──────────────────────────────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────────────┐
│  2. docker-build.yml  ──►  Azure Container Registry      │
│     (push to main or    11 service images pushed         │
│      manual trigger)    as <acr>/<service>:latest        │
└──────────────────────────────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────────────┐
│  3. deploy-aks.yml  ──►  AKS Cluster                     │
│     (manual trigger)    namespace, secrets, deployments   │
└──────────────────────────────────────────────────────────┘
```

---

## Prerequisites: First-Time Setup

### 1. Fill in your GitHub repo details

Edit [infra/terraform/main.tfvars.json](../infra/terraform/main.tfvars.json) and set:

```json
"github_org":  "your-github-username-or-org",
"github_repo": "your-repo-name"
```

### 2. Run Terraform manually (bootstrap)

The GitHub App Registration is created **by** Terraform, so the very first run must be done locally with your own Azure credentials.

```bash
az login
cd infra/terraform
terraform init
terraform apply -var-file="main.tfvars.json" -var="sql_admin_password=YourPassword123!"
```

This creates all Azure infrastructure **and** the App Registration that GitHub Actions will use.

### 3. Copy the client ID to GitHub

After apply completes, note the output:

```
github_client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Go to your GitHub repo → **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret name | Value |
|---|---|
| `AZURE_CLIENT_ID` | Value of `github_client_id` output |
| `AZURE_TENANT_ID` | `8c8f119b-d5c9-4cf8-89f1-8b3f247baabb` |
| `AZURE_SUBSCRIPTION_ID` | `273c270e-9e9a-4ce2-b4a6-5ec9da51fc13` |
| `TF_SQL_ADMIN_PASSWORD` | Your chosen SQL admin password |

From this point on, all pipelines run via OIDC — no passwords or client secrets stored anywhere.

---

## How OIDC Authentication Works

Instead of storing a client secret, the pipeline uses **OpenID Connect (OIDC)**:

1. GitHub generates a short-lived JWT token signed by `token.actions.githubusercontent.com`
2. Azure trusts this issuer because we created a **Federated Identity Credential** in the App Registration (via Terraform)
3. The `azure/login` action exchanges the GitHub token for an Azure access token
4. The pipeline runs with the permissions granted to the Service Principal (Owner on subscription)

No secret ever leaves GitHub or Azure. The token is valid only for the duration of the job.

---

## Pipeline 1: Terraform — `terraform.yml`

**Trigger:** Manual only (`Actions → Terraform → Run workflow`)

**Inputs:**
- `action` — choose `apply` (create/update) or `destroy` (tear down everything)

**What it does:**
1. Authenticates to Azure via OIDC
2. Runs `terraform init` → `terraform validate`
3. Applies or destroys all infrastructure
4. On `apply`: prints key outputs (AKS name, ACR login server, etc.)

**When to use:**
- `apply` — first time setting up the project, or after infrastructure changes in `main.tf`
- `destroy` — tear down all Azure resources to stop billing

> **Note on Terraform state:** The state file (`terraform.tfstate`) is stored in the repo. This works for a demo or single-person project. For a team, migrate to an [Azure Blob Storage backend](https://developer.hashicorp.com/terraform/language/backend/azurerm) to share state safely.

---

## Pipeline 2: Build & Push Docker Images — `docker-build.yml`

**Trigger:**
- **Automatic** — any push to `main` (excluding changes to `infra/`, `k8s/`, `docs/`)
- **Manual** — `Actions → Build and Push Docker Images → Run workflow` (optionally specify an image tag)

**What it does:**
1. Reads the ACR login server from Terraform state
2. Logs into ACR
3. Runs **11 parallel build jobs** — one per service
4. Each job: `docker build --build-arg PROJECT_PATH=<service.csproj> -t <acr>/<service>:<tag> --push .`

**Services built:**

| Image name | .NET project |
|---|---|
| `eventcatalog` | GloboTicket.Services.EventCatalog |
| `shoppingbasket` | GloboTicket.Services.ShoppingBasket |
| `paymentgateway` | External.PaymentGateway |
| `ordering` | GloboTicket.Services.Order |
| `payment` | GloboTicket.Services.Payment |
| `discount` | GloboTicket.Services.Discount |
| `marketing` | GloboTicket.Services.Marketing |
| `gateway-webbff` | GloboTicket.Gateway.WebBff |
| `gateway-mobilebff` | GloboTicket.Gateway.MobileBff |
| `web-bff` | GloboTicket.Web.Bff |
| `webclient` | GloboTicket.Client |

**Image tagging:** Default is `latest`. Use the manual trigger with a custom tag (e.g., `v1.2.0`) when you want versioned images.

---

## Pipeline 3: Deploy to AKS — `deploy-aks.yml`

**Trigger:** Manual only (`Actions → Deploy to AKS → Run workflow`)

**What it does:**
1. Reads infrastructure details from Terraform outputs
2. Gets `kubectl` credentials for the AKS cluster
3. Substitutes placeholder values in K8s manifests:
   - `__ACR_LOGIN_SERVER__` → actual ACR URL
   - `__KEY_VAULT_NAME__` → actual Key Vault name
   - `__KV_PROVIDER_CLIENT_ID__` → managed identity client ID for CSI driver
   - `__TENANT_ID__` → Azure tenant ID
4. Applies manifests in order: namespace → SecretProviderClass → all deployments
5. Shows pod and service status

**Why manual?** Deployment to a shared/production cluster is a deliberate action. You control exactly when new images are rolled out.

---

## Recommended Workflow

### First time (complete setup)

```
1. Edit main.tfvars.json  (github_org, github_repo)
2. az login + terraform apply  (bootstrap — see Prerequisites above)
3. Add 4 GitHub secrets
4. Run: Build and Push Docker Images  (push all images to ACR)
5. Run: Deploy to AKS  (deploy all services to the cluster)
6. kubectl get svc -n globoticket  (find the webclient external IP)
```

### Iterating on code

```
1. Push changes to main
   → Build pipeline triggers automatically
   → 11 images rebuilt and pushed to ACR
2. Run: Deploy to AKS
   → New images rolled out to the cluster
```

### Changing infrastructure

```
1. Edit infra/terraform/main.tf
2. Push to main
3. Run: Terraform → apply
```

### Tearing down

```
Run: Terraform → destroy
```

---

## Security Notes

- The Service Principal has **Owner** on the subscription because Terraform itself creates role assignments. For a production hardening step, you can split this into separate roles: `Contributor` for resource management + `User Access Administrator` scoped only to the resource group.
- The `terraform.tfstate` file **contains sensitive values** (connection strings, etc.) in plaintext. Consider using the [azurerm backend](https://developer.hashicorp.com/terraform/language/backend/azurerm) with an encrypted Storage Account and restricted access for team projects.
- The SQL admin password is never stored in the repo — it is always passed at runtime from the `TF_SQL_ADMIN_PASSWORD` GitHub secret.
