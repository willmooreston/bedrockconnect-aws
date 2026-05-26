# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Deploys [BedrockConnect](https://github.com/Pugmatt/BedrockConnect) on AWS free tier — lets console players (Xbox, Switch, PlayStation) use a custom Minecraft Bedrock server list by pointing their router's DNS at the Elastic IP.

## Commands

```bash
# Local validation (requires OpenTofu ≥ 1.6 and AWS credentials)
cd tofu
tofu init
tofu fmt -recursive          # format all .tf files
tofu fmt -check -recursive   # check formatting (what CI runs)
tofu validate
tofu plan

# Bootstrap (one-time, before first deploy)
cd tofu/bootstrap
tofu init && tofu apply

# Build bind9 image locally
docker build -t bedrockconnect-bind9 ./bind9

# Get the deployed public IP
cd tofu && tofu output public_ip
```

## Architecture

Two ECS services run on a single **t2.micro** EC2 instance using **host network mode** (no load balancer, no VPC CNI overhead):

- **bedrockconnect** (`pugmatt/bedrock-connect`) — listens on `19132/UDP`, intercepts the Minecraft Bedrock server list and serves a custom one
- **bind9** (custom image in ECR) — listens on `53/UDP`, hijacks featured server hostnames to redirect to the same EC2 instance

The EC2 instance gets an **Elastic IP** at provision time, so its public IP is stable across reboots. The bind9 container discovers this IP at startup by querying the EC2 **IMDSv2** metadata endpoint and generates named zone files dynamically — no static config needed when the IP changes.

**State:** OpenTofu remote state lives in S3 (`bedrockconnect-tofu-state`) using native S3 locking (`use_lockfile = true`). No DynamoDB needed.

**Auth:** GitHub Actions workflows are currently disabled (`.github/workflows/*.disabled`). The bootstrap still provisions the OIDC role for when CI is re-enabled.

**IP allowlisting:** Security group restricts ports 19132 and 53 to CIDRs in `tofu/terraform.tfvars` (gitignored). See `tofu/example.tfvars` for the format.

## CI/CD Flow (currently disabled)

**PR:** `tofu fmt -check` → `tofu validate` → `tofu plan` → plan posted as PR comment.

**Push to main (apply):**
1. `tofu apply -target=module.ecs_cluster.aws_ecr_repository.bind9` — creates ECR repo if it doesn't exist
2. Builds and pushes `./bind9` Docker image tagged with `github.sha`
3. `tofu apply -var="bind9_image_uri=<ECR_URL>:<sha>"` — full apply

The ECR target-apply before the image build is intentional: the repo must exist before `docker push`. When re-enabling CI, pass allowed CIDRs via a `TF_VAR_allowed_ipv6_cidrs` Actions secret.

## Key Design Constraints

- **Host networking on ECS/EC2:** Both task definitions use `network_mode = "host"`. This is required because UDP port mapping with bridge networking is unreliable on ECS; host mode binds directly to the EC2 NIC.
- **bind9 IP self-discovery:** `bind9/entrypoint.sh` runs at container start, hits IMDSv2, and writes all zone files before starting `named`. If the container restarts (e.g., after an EC2 reboot), it re-queries metadata and picks up any new IP automatically.
- **bedrockconnect image:** Uses the upstream public image `pugmatt/bedrock-connect` directly — no custom build needed.
- **ECR lifecycle policy:** Keeps only the last 5 images to avoid storage costs.

## Module Boundaries

- `tofu/modules/networking/` — VPC, public subnet, IGW, route table, Elastic IP allocation. Outputs `vpc_id`, `subnet_id`, `eip_allocation_id`.
- `tofu/modules/ecs-cluster/` — everything that runs on the instance: security group, IAM roles, EC2, ECS cluster + services + task definitions, ECR repo, CloudWatch log groups.
- `tofu/bootstrap/` — separate state, run once manually: S3 state bucket, GitHub OIDC provider, GitHub Actions IAM role.
