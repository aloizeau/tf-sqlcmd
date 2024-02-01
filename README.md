# tf-sqlcmd

# Introduction

L'évolution constante des infrastructures cloud a radicalement transformé la manière dont nous gérons et maintenons nos bases de données. 

Dans ce paysage en mutation, la gestion efficace des performances des bases de données devient un impératif pour assurer la disponibilité, la réactivité et la fiabilité des applications critiques.

L'automatisation des tâches de gestion et d'optimisation devient un élément crucial pour garantir des performances optimales et une utilisation efficace des ressources. L'une des fonctionnalités clés offertes par Azure SQL Database est l'option d'auto-tuning, qui ajuste automatiquement les paramètres de configuration de la base de données pour optimiser les performances en fonction des charges de travail.

En combinant les capacités de Terraform et les fonctionnalités avancées d'Azure SQL Database, je vais vous démontrer comment gérer la configuration des performances des bases de données dans un environnement cloud moderne.

# Déploiement d'un service Azure SQL via Terraform

## Azure SQL  Database

Le déploiement d'une base de données dans le cloud est une étape fondamentale dans le cycle de développement d'une application. Terraform, en tant qu'outil d'infrastructure en tant que code (IaC), offre une approche cohérente et reproductible pour provisionner et gérer des ressources cloud, y compris les bases de données.

Le code Terraform ci-dessous illustre une manière simple et efficace de déployer une base de données Azure SQL Database dans votre environnement Azure:

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

  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = true
  }
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

## Data

Comme vous pouvez le voir j'utilise ici plusieurs data Terraform me permettant de récupérer des informations liées à mon contexte d'exécution :

data "azurerm_client_config" "current" {
}

data "http" "currentip" {
  url = "https://ipv4.icanhazip.com"
}

## Variables

Pour plus de simplicité, voici le fichier de variables utilisées:

variable "init_script_file" {
  type    = string
  default = "./init_script.sql"
}
variable "sql_admin_username" {
  type    = string
  default = "4dm1n157r470r"
}
variable "sql_admin_password" {
  type    = string
  default = "4-v3ry-53cr37-p455w0rd"
}
variable "log_file" {
  type    = string
  default = "./log.txt"
}
variable "db_name" {
  type    = string
  default = "mysampledb"
}
variable "tenant_id" {
  type    = string
  default = "8d8178c0-ec3d-41a7-a674-d610a2fc1d1b"
}
variable "subscription_id" {
  type    = string
  default = "35a9e8c3-ab8b-4b0a-83f7-3817ea2d3bfd"
}

# Post configuration via un script SQL

Le null_resource est un type de ressource Terraform utilisé pour définir des actions ou des configurations qui ne sont pas directement prises en charge par les fournisseurs cloud natifs ou pour exécuter des opérations qui ne créent pas de ressources explicites dans l'infrastructure cloud.

Dans le contexte d'Azure et de l'exécution de scripts SQL, le null_resource peut être utilisé pour déclencher l'exécution d'un script SQL après le déploiement d'autres ressources, comme une base de données Azure SQL.

Voici un exemple de l'utilisation du null_resource pour exécuter un script SQL dans un contexte Azure avec Terraform :

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

En résumé, le null_resource avec le provisioner local-exec permet d'exécuter des actions personnalisées, comme l'exécution de scripts SQL, dans un contexte Azure avec Terraform.

Dans mon exemple, mon fichier SQL nommé init_script.sql, contient la commande suivante me permettant l'activation de l'option d'automatic tuning:

-- Enable automatic tuning on an individual database
ALTER DATABASE current SET AUTOMATIC_TUNING (CREATE_INDEX = ON);

Il faudra bien sûr installer l'outil sqlcmdsur la machine ou le container exécutant ce code terraform.

# GitHub repository

Vous pouvez accéder au code source complet utilisé pour déployer une base de données Azure SQL Database avec Terraform dans mon référentiel GitHub. 

Ce référentiel contient non seulement le code Terraform présenté dans cet article, mais également d'autres ressources et configurations connexes pour faciliter le déploiement et la gestion de vos infrastructures cloud.

Lien vers le code source

N'hésitez pas à explorer le code, à le cloner localement et à l'adapter à vos besoins spécifiques. Vous pouvez également contribuer en proposant des améliorations ou en partageant vos propres expériences et bonnes pratiques pour le déploiement et la gestion des bases de données dans Azure avec Terraform.

Liens utiles

Documentation Microsoft : Enable automatic tuning on an individual database

Hashicrorp Terraform: null_resource

sqlcmd : Utility overview for Azure SQL