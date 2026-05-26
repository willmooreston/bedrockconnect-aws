variable "aws_region" {
  default = "us-west-2"
}

variable "project" {
  default = "bedrockconnect"
}

variable "bind9_image_uri" {
  description = "ECR image URI for bind9, set by CI after image push"
  default     = "public.ecr.aws/ubuntu/bind9:latest"
}

variable "allowed_ipv4_cidrs" {
  description = "IPv4 CIDRs allowed to reach BedrockConnect and bind9"
  type        = list(string)
  default     = []
}

variable "allowed_ipv6_cidrs" {
  description = "IPv6 CIDRs allowed to reach BedrockConnect and bind9"
  type        = list(string)
  default     = []
}
