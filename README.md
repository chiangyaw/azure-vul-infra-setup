# Terraform Azure DevOps Environment Provisioner

This Terraform configuration provisions a complete Azure CI/CD environment, including multiple Azure Kubernetes Service (AKS) clusters, publicly accessible storage for testing, a Container Registry (ACR), and a dedicated Jenkins build server.

## ⚠️ WARNING: Public Accessibility

This template explicitly configures resources for **public accessibility** (Container Registry Admin Access, Public IP for Jenkins, Open Network Rules on Storage). **This is not recommended for production environments.** It is designed for quick testing/dev environments.

## Prerequisites

1.  **Azure Account and Subscription**
2.  **Terraform CLI** installed.
3.  **Azure CLI** installed and authenticated (`az login`).
4.  A local file named **`1-MB-Test-SensitiveData.xlsx`** must exist in the root directory for the storage blob upload step.

## Configuration Files

The repository should contain the following files:

* `main.tf`: Main resource declarations and provisioning logic.
* `variables.tf`: All configurable input variables.
* `outputs.tf`: Outputs relevant information like Jenkins URL and Public IPs.

## Deployment Steps

### 1. Initialize Terraform

Navigate to your project directory and initialize the backend and providers.

```bash
terraform init
````

### 2\. Configure Variables

You must supply values for the required variables: `resource_group_name`, `acr_name`, and `vm_admin_password`.

| Variable | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `resource_group_name` | Name of the Resource Group to use (existing or new). | Yes | N/A |
| `acr_name` | Globally unique name for the Azure Container Registry. | Yes | N/A |
| `vm_admin_password` | Admin password for the Ubuntu VM (sensitive). | Yes | N/A |
| `use_existing_resource_group` | Set to `true` to use an existing RG. | No | `false` |
| `aks_count` | Number of AKS clusters and associated storage accounts to create. | No | `2` |

### 3\. Plan and Apply

Use the `-var` flag to pass required variables.

#### Option A: Creating a New Resource Group

```bash
terraform apply \
  -var 'resource_group_name=my-new-dev-rg' \
  -var 'acr_name=myuniquedevacr' \
  -var 'vm_admin_password=S3cureP@ssw0rd1234'
```

#### Option B: Utilizing an Existing Resource Group

```bash
terraform apply \
  -var 'resource_group_name=my-existing-rg' \
  -var 'use_existing_resource_group=true' \
  -var 'acr_name=myuniquedevacr' \
  -var 'vm_admin_password=S3cureP@ssw0rd1234'
```

## Deployed Resources

| Resource | Count | Public Access | Notes |
| :--- | :--- | :--- | :--- |
| **Azure Kubernetes Service (AKS)** | `var.aks_count` | Yes (Public endpoint) | Ready for container deployment. |
| **Azure Storage Account (Blob)** | `var.aks_count` | Configured with `ip_rules=["0.0.0.0/0"]` to bypass strict policies. | Each container has the `1-MB-Test-SensitiveData.xlsx` file uploaded. |
| **Azure Container Registry (ACR)** | 1 | Yes (Admin user enabled) | Basic SKU is used for public image storage. |
| **Ubuntu VM (Jenkins)** | 1 | Yes (Public IP) | Automatically installs Java, **Docker**, and **Jenkins** on port `8080`. |

## Post-Deployment Access

1.  **Jenkins Access**: Get the public URL from the `jenkins_url` output.

2.  **Jenkins Initial Password**: SSH into the Ubuntu VM using the `jenkins_vm_public_ip` output and the provided admin credentials, then run:

    ```bash
    sudo cat /var/lib/jenkins/secrets/initialAdminPassword
    ```

## Cleanup

To destroy all resources provisioned by this template:

```bash
terraform destroy \
  -var 'resource_group_name=<USED_RG_NAME>' \
  -var 'acr_name=<USED_ACR_NAME>' \
  -var 'vm_admin_password=<USED_PASSWORD>' \
  # Include '-var use_existing_resource_group=true' if you used an existing RG
```

**Note**: If you used an **existing** Resource Group, the `terraform destroy` command will only remove the resources *created* by this script (AKS, ACR, VM, Storage) but will **not** delete the Resource Group itself.

```
```