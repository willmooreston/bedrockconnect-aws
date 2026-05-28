#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TOFU_DIR="$REPO_ROOT/tofu"
BIND9_DIR="$REPO_ROOT/bind9"

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! docker info &>/dev/null; then
  echo "Error: Docker daemon is not running. Start Docker Desktop (or your Docker daemon) and try again." >&2
  exit 1
fi

# ── Auth check ────────────────────────────────────────────────────────────────
if ! aws sts get-caller-identity &>/dev/null; then
  echo "No active AWS session — running aws login..."
  aws login
fi

# ── Resolve ECR repo URL from tofu state ──────────────────────────────────────
echo "Fetching ECR repo URL from tofu state..."
ECR_REPO_URL=$(cd "$TOFU_DIR" && tofu output -raw ecr_repository_url 2>/dev/null || true)
if [[ -z "$ECR_REPO_URL" ]]; then
  echo "Error: ecr_repository_url output is empty — is use_bind9 = true in terraform.tfvars?" >&2
  exit 1
fi
AWS_REGION=$(cd "$TOFU_DIR" && tofu output -raw aws_region 2>/dev/null || echo "us-west-2")
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

IMAGE_TAG=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
IMAGE_URI="$ECR_REPO_URL:$IMAGE_TAG"

# ── Ensure ECR repo exists ────────────────────────────────────────────────────
echo "Ensuring ECR repository exists..."
cd "$TOFU_DIR"
tofu apply -target=module.ecs_cluster.aws_ecr_repository.bind9 -auto-approve

# ── Build & push ──────────────────────────────────────────────────────────────
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "Building bind9 image ($IMAGE_TAG)..."
docker build -t "$IMAGE_URI" "$BIND9_DIR"

echo "Pushing $IMAGE_URI..."
docker push "$IMAGE_URI"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo "Deploying with new image..."
cd "$TOFU_DIR"
tofu apply -var="bind9_image_uri=$IMAGE_URI"

echo "Done. bind9 image: $IMAGE_URI"
