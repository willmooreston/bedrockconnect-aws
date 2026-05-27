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

variable "aws_region" {
  default = "us-west-2"
}

variable "project" {
  default = "bedrockconnect"
}

variable "github_repo" {
  default = "willmooreston/bedrockconnect-aws"
}

# S3 bucket for OpenTofu remote state
resource "aws_s3_bucket" "tofu_state" {
  bucket = "${var.project}-tofu-state"
}

resource "aws_s3_bucket_versioning" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tofu_state" {
  bucket                  = aws_s3_bucket.tofu_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# GitHub OIDC provider — allows Actions to assume AWS roles without stored keys
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "${var.project}-github-actions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBackend"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.tofu_state.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.tofu_state.bucket}/*",
        ]
      },
      {
        Sid    = "DeployPermissions"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "ecs:*",
          "ecr:*",
          "iam:*",
          "logs:*",
          "cloudwatch:*",
          "s3:*",
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = "*"
      },
    ]
  })
}

output "state_bucket_name" {
  value = aws_s3_bucket.tofu_state.bucket
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
