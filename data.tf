data "azurerm_client_config" "current" {
}

data "http" "currentip" {
  url = "https://ipv4.icanhazip.com"
}