module "naming" {
  source  = "codectl/naming/azure"
  version = "~> 0.1"

  suffix = ["demo", "dev"]
}

module "regions" {
  source  = "codectl/locations/azure"
  version = "~> 1.0"

  location = {
    primary = "germanywestcentral"
  }
}

module "rg" {
  source  = "codectl/rg/azure"
  version = "~> 1.0"

  groups = {
    syn = {
      name     = module.naming.resource_group.name_unique
      location = module.regions.location.primary.name
    }
  }
}

module "storage" {
  source  = "codectl/sa/azure"
  version = "~> 1.0"

  storage = {
    name                = module.naming.storage_account.name_unique
    location            = module.rg.groups.syn.location
    resource_group_name = module.rg.groups.syn.name
    is_hns_enabled      = true

    file_systems = {
      adls-gen2 = {
        name = module.naming.storage_data_lake_gen2_filesystem.name
      }
    }
  }
}

module "kv" {
  source  = "codectl/kv/azure"
  version = "~> 1.0"

  vault = {
    name                = module.naming.key_vault.name_unique
    location            = module.rg.groups.syn.location
    resource_group_name = module.rg.groups.syn.name

    secrets = {
      random_string = {
        synapse-admin-password = {
          length      = 24
          special     = true
          min_special = 2
          min_upper   = 2
        }
      }
    }
  }
}

module "synapse" {
  source  = "codectl/syn/azure"
  version = "~> 1.0"

  workspace = {
    name                                 = module.naming.synapse_workspace.name_unique
    storage_data_lake_gen2_filesystem_id = module.storage.file_systems.adls-gen2.id
    location                             = module.rg.groups.syn.location
    resource_group_name                  = module.rg.groups.syn.name
    sql_administrator_login              = "sqladminuser"
    sql_administrator_login_password     = module.kv.secrets.synapse-admin-password.value
    managed_virtual_network_enabled      = true

    identity = {
      type = "SystemAssigned"
    }

    # managed private endpoints are created via the workspace dev endpoint
    # (data plane), so the client running terraform must be allowed through
    firewall_rule = {
      allow_all = {
        name             = "AllowAll"
        start_ip_address = "0.0.0.0"
        end_ip_address   = "255.255.255.255"
      }
    }

    managed_private_endpoint = {
      blob = {
        name               = module.naming.synapse_managed_private_endpoint.name
        target_resource_id = module.storage.account.id
        subresource_name   = "blob"
      }
    }
  }
}
