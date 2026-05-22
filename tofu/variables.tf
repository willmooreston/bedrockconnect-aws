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
