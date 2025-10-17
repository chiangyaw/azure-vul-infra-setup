# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# 1. Resource Group Conditional Logic

# Data source for an existing Resource Group (used if var.use_existing_resource_group is true)
data "azurerm_resource_group" "existing" {
  count = var.use_existing_resource_group ? 1 : 0
  name  = var.resource_group_name
}

# Resource to create a new Resource Group (used if var.use_existing_resource_group is false)
resource "azurerm_resource_group" "new" {
  count    = var.use_existing_resource_group ? 0 : 1
  name     = var.resource_group_name
  location = var.location
}

# Local variable to reference the correct Resource Group object throughout the rest of the configuration
locals {
  # If 'use_existing_resource_group' is true, reference the data source.
  # If false, reference the created resource.
  rg = var.use_existing_resource_group ? data.azurerm_resource_group.existing[0] : azurerm_resource_group.new[0]
}

# All subsequent resources now reference locals.rg.name and locals.rg.location

# 2. Azure Container Registry (ACR) - Publicly Accessible
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name 
  location            = local.rg.location
  resource_group_name = local.rg.name
  sku                 = "Basic"
  admin_enabled       = true 

  public_network_access_enabled = true
}

# 3. Multiple AKS Clusters (Controlled by var.aks_count)
resource "azurerm_kubernetes_cluster" "aks" {
  count               = var.aks_count
  name                = "aks-cluster-${count.index}"
  location            = local.rg.location
  resource_group_name = local.rg.name
  dns_prefix          = "aks-cluster-dns-${count.index}"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

# 4. Multiple Publicly Accessible Blob Storages (Controlled by var.aks_count)
resource "azurerm_storage_account" "blob_storage" {
  count                    = var.aks_count
  # Note: Storage account names must be globally unique, so we'll still construct a unique name based on the RG name.
  name                     = "st${replace(local.rg.name, "-", "")}blob${count.index}" 
  resource_group_name      = local.rg.name
  location                 = local.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "container" {
  count                 = var.aks_count
  name                  = "public-data-${count.index}"
  storage_account_name  = azurerm_storage_account.blob_storage[count.index].name
  container_access_type = "blob" 
}

# Upload the sample file to each storage container
resource "azurerm_storage_blob" "sample_file_blob" {
  count                  = var.aks_count
  name                   = "1-MB-Test-SensitiveData.xlsx"
  storage_account_name   = azurerm_storage_account.blob_storage[count.index].name
  storage_container_name = azurerm_storage_container.container[count.index].name
  type                   = "Block"
  source                 = "1-MB-Test-SensitiveData.xlsx" 
}

# 5. Ubuntu VM with Jenkins (Publicly Accessible)
# Network and IP
# NOTE: VNET/Subnet/NIC/VM must be created in the local.rg.name/location
resource "azurerm_public_ip" "jenkins_ip" {
  name                = "jenkins-vm-public-ip"
  location            = local.rg.location
  resource_group_name = local.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "jenkins_nsg" {
  name                = "jenkins-vm-nsg"
  location            = local.rg.location
  resource_group_name = local.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" 
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Jenkins_HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080" 
    source_address_prefix      = "*" 
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-jenkins"
  location            = local.rg.location
  resource_group_name = local.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-jenkins"
  resource_group_name  = local.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_interface" "jenkins_nic" {
  name                = "jenkins-vm-nic"
  location            = local.rg.location
  resource_group_name = local.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jenkins_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.jenkins_nic.id
  network_security_group_id = azurerm_network_security_group.jenkins_nsg.id
}

# Cloud-Init script for Jenkins and Docker installation
data "cloudinit_config" "jenkins_init" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "install_jenkins_docker.sh"
    content_type = "text/x-shellscript"
    content = <<-EOF
      #!/bin/bash
      sudo apt update -y
      
      # --- 1. INSTALL DOCKER ---
      # Install packages to allow apt to use a repository over HTTPS
      sudo apt install -y ca-certificates curl gnupg lsb-release
      
      # Add Docker's official GPG key
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      
      # Set up the repository
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      # Install Docker Engine and related tools
      sudo apt update -y
      sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      
      # Add the VM admin user to the docker group
      sudo usermod -aG docker ${var.vm_admin_username}
      
      # --- 2. INSTALL JENKINS ---
      # Install Java - Jenkins requirement
      sudo apt install openjdk-11-jdk -y
      
      # Add Jenkins repo key and source list
      curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
      echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
      
      # Install Jenkins
      sudo apt update -y
      sudo apt install jenkins -y
      
      # Add jenkins user to the docker group to allow Jenkins jobs to run docker commands
      sudo usermod -aG docker jenkins
      
      sudo systemctl start jenkins
      sudo systemctl enable jenkins
      
      # Wait briefly for Jenkins to start and create initial admin password file
      sleep 30
    EOF
  }
}

# The Ubuntu VM
resource "azurerm_linux_virtual_machine" "jenkins_vm" {
  name                  = "jenkins-ubuntu-vm"
  location              = local.rg.location
  resource_group_name   = local.rg.name
  size                  = var.vm_size
  admin_username        = var.vm_admin_username
  admin_password        = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.jenkins_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal" 
    sku       = "20_04-lts"
    version   = "latest"
  }
  
  # Automatically install Jenkins and Docker via cloud-init
  custom_data = data.cloudinit_config.jenkins_init.rendered
}