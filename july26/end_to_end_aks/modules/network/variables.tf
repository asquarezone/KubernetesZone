variable "suffix"   { type = string }
variable "location" { type = string }
variable "tags"     { type = map(string) }

variable "vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
variable "system_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}
variable "user_subnet_cidr" {
  type    = string
  default = "10.10.2.0/23"
}
variable "appgw_subnet_cidr" {
  type    = string
  default = "10.10.10.0/27"
}
