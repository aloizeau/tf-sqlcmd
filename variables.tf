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