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
    name                     = module.naming.key_vault.name_unique
    location                 = module.rg.groups.syn.location
    resource_group_name      = module.rg.groups.syn.name
    purge_protection_enabled = true

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

    keys = {
      workspace-encryption-key = {
        key_type = "RSA"
        key_size = 2048
        key_opts = [
          "sign", "unwrapKey",
          "verify", "wrapKey"
        ]
      }
    }
  }
}

module "uai" {
  source  = "codectl/uai/azure"
  version = "~> 1.0"

  identity = {
    name                = module.naming.user_assigned_identity.name
    location            = module.rg.groups.syn.location
    resource_group_name = module.rg.groups.syn.name
  }
}

module "rbac" {
  source  = "codectl/rbac/azure"
  version = "~> 1.0"

  role_assignments = {
    synapse_uai = {
      object_id = module.uai.identity.principal_id
      type      = "ServicePrincipal"
      roles = {
        "Key Vault Crypto Service Encryption User" = {
          scopes = {
            kv = {
              id = module.kv.vault.id
            }
          }
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

    identity = {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [module.uai.identity.id]
    }

    customer_managed_key = {
      key_versionless_id        = module.kv.keys.workspace-encryption-key.versionless_id
      key_name                  = module.kv.keys.workspace-encryption-key.name
      user_assigned_identity_id = module.uai.identity.id
    }
  }
}
