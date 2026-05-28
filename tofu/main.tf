terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source  = "./modules/networking"
  project = var.project
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  project             = var.project
  aws_region          = var.aws_region
  vpc_id              = module.networking.vpc_id
  subnet_id           = module.networking.subnet_id
  eip_allocation_id   = module.networking.eip_allocation_id
  use_bind9           = var.use_bind9
  bind9_image_uri     = var.bind9_image_uri
  allowed_ipv4_cidrs  = var.allowed_ipv4_cidrs
  allowed_ipv6_cidrs  = var.allowed_ipv6_cidrs
}
