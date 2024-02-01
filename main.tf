terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.89.0"
    }
  }
}

provider "azurerm" {
  tenant_id                  = var.tenant_id
  subscription_id            = var.subscription_id
  skip_provider_registration = true # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-sqlcmd"
  location = "West Europe"
}

resource "azurerm_mssql_server" "server" {
  name                          = "alusampledbsetup"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "12.0"
  administrator_login           = var.sql_admin_username
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  azuread_administrator {
    login_username              = "UnknowUserName" # Not validated by Entra ID
    object_id                   = data.azurerm_client_config.current.client_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = false
  }

  tags = {
    environment = "poc"
  }
}

resource "azurerm_mssql_database" "db" {
  name                        = var.db_name
  server_id                   = azurerm_mssql_server.server.id
  collation                   = "SQL_Latin1_General_CP1_CI_AS"
  auto_pause_delay_in_minutes = -1
  min_capacity                = 1
  max_size_gb                 = 1
  sku_name                    = "GP_S_Gen5_2"

  long_term_retention_policy {
    monthly_retention = "P1M"
  }
  short_term_retention_policy {
    retention_days           = 35
    backup_interval_in_hours = 24
  }

  tags = {
    environment = "poc"
  }

  #   # prevent the possibility of accidental data loss
  #   lifecycle {
  #     prevent_destroy = true
  #   }
}

resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "Azure Services"
  server_id        = azurerm_mssql_server.server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "current_ip" {
  name             = "MyCurrentIP"
  server_id        = azurerm_mssql_server.server.id
  start_ip_address = chomp(data.http.currentip.response_body)
  end_ip_address   = chomp(data.http.currentip.response_body)
}

resource "null_resource" "init_sql_db" {
  depends_on = [azurerm_mssql_database.db, azurerm_mssql_firewall_rule.current_ip]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    environment = {
      SQLCMDPASSWORD = var.sql_admin_password # Required so that the password does not spill to console when the resource fails
    }
    command = "sqlcmd -U ${var.sql_admin_username} -S alusampledbsetup.database.windows.net -d ${var.db_name} -i ${var.init_script_file} -o ${var.log_file}"
  }
}