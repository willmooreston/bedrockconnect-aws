variable "project" {}
variable "aws_region" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "eip_allocation_id" {}

variable "use_bind9" {
  type    = bool
  default = true
}

variable "bind9_image_uri" {
  description = "bind9 container image URI (ECR). Ignored when use_bind9 = false."
  default     = ""
}

variable "bedrockconnect_image" {
  default = "pugmatt/bedrock-connect:latest"
}

variable "allowed_ipv4_cidrs" {
  type    = list(string)
  default = []
}

variable "allowed_ipv6_cidrs" {
  type    = list(string)
  default = []
}
