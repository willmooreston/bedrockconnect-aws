variable "aws_region" {
  default = "us-west-2"
}

variable "project" {
  default = "bedrockconnect"
}

variable "use_bind9" {
  description = "Deploy bind9 DNS on EC2. Set to false when using a local DNS resolver (e.g. Pi with dnsmasq)."
  type        = bool
  default     = true
}

variable "bind9_image_uri" {
  description = "ECR image URI for bind9, set by CI after image push. Ignored when use_bind9 = false."
  default     = ""
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
