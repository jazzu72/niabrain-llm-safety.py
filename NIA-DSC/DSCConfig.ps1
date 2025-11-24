<#
.SYNOPSIS
NIA Quantum Platform - PowerShell Desired State Configuration

This creates per-node DSC MOF files for:
- NIA Decision Engine service
- Required Windows Features
- Folder structure provisioning
- Scheduled maintenance scripts
- Quantum Engine prerequisites
- Log directories
- Environment variables
- NIA Windows Service installation

Output goes into: .\output\<nodeName>\
#>

configuration NIA_QuantumNode_Config {

    param(
        [Parameter(Mandatory=$true)]
        [String[]]$NodeNames,

        [Parameter(Mandatory=$false)]
        [String]$ServiceExePath = "C:\NIA\services\decision-engine\NiaDecisionEngine.exe",

        [Parameter(Mandatory=$false)]
        [String]$LogRoot = "C:\NIA\logs",

        [Parameter(Mandatory=$false)]
        [String]$EnvFile = "C:\NIA\env\nia.env"
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node $NodeNames {

        # -----------------------------------------------------
        # Basic Folder Structure
        # -----------------------------------------------------
        File NIA_MainFolder {
            DestinationPath = "C:\NIA"
            Type = "Directory"
            Ensure = "Present"
        }

        File NIA_ServiceFolder {
            DestinationPath = "C:\NIA\services"
            Type = "Directory"
            Ensure = "Present"
        }

        File NIA_DecisionEngineFolder {
            DestinationPath = "C:\NIA\services\decision-engine"
            Type = "Directory"
            Ensure = "Present"
        }

        File NIA_LogRoot {
            DestinationPath = $LogRoot
            Type = "Directory"
            Ensure = "Present"
        }


        # -----------------------------------------------------
        # Environment File
        # -----------------------------------------------------
        File NIA_EnvFile {
            DestinationPath = $EnvFile
            Type = "File"
            Ensure = "Present"
            Contents = @"
XAI_API_KEY=
GPT5_API_KEY=
NIA_ENVIRONMENT=PRODUCTION
"@
        }

        # -----------------------------------------------------
        # Windows Feature Requirements
        # -----------------------------------------------------
        WindowsFeature NetFramework {
            Ensure = "Present"
            Name = "NET-Framework-45-Core"
        }


        # -----------------------------------------------------
        # NIA Decision Engine Windows Service
        # -----------------------------------------------------
        Service NIA_DecisionEngine_Service {
            Name = "NIA.DecisionEngine"
            StartupType = "Automatic"
            State = "Running"
            Path = $ServiceExePath
            DependsOn = "[File]NIA_DecisionEngineFolder"
        }


        # -----------------------------------------------------
        # Scheduled Daily Maintenance
        # -----------------------------------------------------
        Script NIA_DailyMaintenance {
            GetScript = { @{ Result = "OK" } }
            TestScript = { $true }
            SetScript = {
                $taskName = "NIA Daily Maintenance"
                $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\NIA\services\maintenance.ps1"
                $trigger = New-ScheduledTaskTrigger -Daily -At 3am

                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force
            }
            DependsOn = "[File]NIA_MainFolder"
        }


        # -----------------------------------------------------
        # Create maintenance script
        # -----------------------------------------------------
        File NIA_MaintenanceScript {
            DestinationPath = "C:\NIA\services\maintenance.ps1"
            Type = "File"
            Ensure = "Present"
            Contents = @"
# NIA Quantum Node Maintenance Script
Write-Output "Running NIA node maintenance..."
Get-Service | Out-Null
"@
        }

    } # Node block end

} # Configuration end



# ----------------------------------------------------------------
# EXECUTION WRAPPER (called by Generate-LCMMetaConfig.ps1)
# ----------------------------------------------------------------
param(
    [Parameter(Mandatory=$true)]
    [String[]]$Nodes,

    [Parameter(Mandatory=$true)]
    [String]$OutputPath
)

Write-Host "Generating NIA DSC MOFs..." -ForegroundColor Cyan

NIA_QuantumNode_Config `
    -NodeNames $Nodes `
    -OutputPath $OutputPath

Write-Host "✅ NIA DSC MOF generation complete." -ForegroundColor Green
Write-Host "MOFs located in: $OutputPath" .\.github- name: Compile DSC (Cross-platform PowerShell Core)
  shell: pwsh
  run: |
    ./dsc/windows-node-config.ps1
nia-decision-engine
chart: nia-decision-engine
version: '>=0.1.0'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nia-decision-engine
  namespace: nia
spec:
  interval: 5m
  chart:
    spec:
      chart: nia-decision-engine
      version: '>=0.1.0'
      sourceRef:
        kind: HelmRepository
        name: nia-charts
        namespace: flux-system
      interval: 1m
  values:
    replicaCount: 1
    image:
      repository: ghcr.io/jazzu72/nia-decision-engine
      pullPolicy: IfNotPresent
      tag: "latest"
    service:
      type: ClusterIP
      port: 8080
    env:
      XAI_API_KEY: ""  # Override in Flux or secrets
    autoscaling:
      minReplicas: 1
      maxReplicas: 5
      targetCPUUtilizationPercentage: 80
      targetMemoryUtilizationPercentage: 80
    resources: {}
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: nia-charts
  namespace: flux-system
spec:
  interval: 10m
  url: oci://ghcr.io/jazzu72/charts
- name: Compile DSC (Cross-platform PowerShell Core)
  shell: pwsh
  run: |
    ./dsc/windows-node-config.ps1
git add .
git commit -m "Finalize CI/CD + Flux OCI pipeline"
git push
flux bootstrap github \
  --owner=jazzu72 \
  --repository=nia-decision-engine \
  --branch=main \
  --path=flux
nia-infra (Terraform + Flux)
nia-decision-engine (app + helm)
nia-platform (cross-env cluster mgmt)
clusters/
  prod/
  staging/
  dev/
terraform/
├── README.md
├── versions.tf
├── providers.tf
├── backend.tf        # optional remote state bootstrap (run once)
├── main.tf           # root that calls modules
├── variables.tf
├── outputs.tf
├── modules/
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── acr/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── keyvault/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── aks/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── flux_bootstrap.tf (optional local-exec to run flux bootstrap)
# Terraform: NIA Platform (Azure) - Starter

This Terraform repo provisions:

- Virtual network + subnets
- Azure Container Registry (private)
- Azure Key Vault
- Azure Kubernetes Service (AKS) private cluster with managed identity and OIDC enabled
- Role assignment so AKS can pull from ACR
- Outputs for kubeconfig, ACR login server, KeyVault

## Quickstart

1. Install Terraform (>= 1.5.0), Azure CLI, and login: `az login`
2. Create or set a resource group for remote state (or edit backend.tf)
3. Initialize:

```bash
cd terraform
terraform init
terraform plan -var="subscription_id=..." -var="location=eastus" -var="prefix=nia"
terraform apply -var="subscription_id=..." -var="location=eastus" -var="prefix=nia"
az aks get-credentials --resource-group <rg> --name <aks-name> --admin

---

## `terraform/versions.tf`

```hcl
terraform {
  required_version = ">= 1.4.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.60.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.14.0"
    }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# optional kubernetes provider for post-deploy resources (Flux bootstrap separate)
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}
# Example: configure remote backend (uncomment to enable after you create storage)
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "nia-tfstate-rg"
#     storage_account_name = "niatfstate"
#     container_name       = "tfstate"
#     key                  = "nia-terraform.tfstate"
#   }
# }
variable "subscription_id" {
  type        = string
  description = "Azure subscription id"
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant id"
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus"
}

variable "prefix" {
  type        = string
  description = "Resource name prefix"
  default     = "nia"
}

variable "env" {
  type        = string
  description = "Deployment environment (dev/staging/prod)"
  default     = "dev"
}

variable "node_count" {
  type    = number
  default = 3
}

variable "node_size" {
  type    = string
  default = "Standard_D2s_v3"
}
locals {
  name_prefix = "${var.prefix}-${var.env}"
  resource_group_name = "${local.name_prefix}-rg"
}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = var.location
  tags = {
    environment = var.env
    project     = var.prefix
  }
}

module "network" {
  source      = "./modules/network"
  prefix      = local.name_prefix
  location    = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

module "acr" {
  source      = "./modules/acr"
  prefix      = local.name_prefix
  location    = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku         = "Standard"
}

module "keyvault" {
  source      = "./modules/keyvault"
  prefix      = local.name_prefix
  location    = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id   = var.tenant_id
}

module "aks" {
  source                 = "./modules/aks"
  prefix                 = local.name_prefix
  location               = var.location
  resource_group_name    = azurerm_resource_group.rg.name
  vnet_subnet_id         = module.network.aks_subnet_id
  node_count             = var.node_count
  node_size              = var.node_size
  acr_id                 = module.acr.acr_id
  keyvault_id            = module.keyvault.keyvault_id
  tenant_id              = var.tenant_id
}
