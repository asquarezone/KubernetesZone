variable "suffix"              { type = string }
variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "tags"                { type = map(string) }
variable "sku" {
  type    = string
  default = "Standard"
}
