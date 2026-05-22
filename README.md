# BedrockConnect on AWS

Deploys [BedrockConnect](https://github.com/Pugmatt/BedrockConnect) on AWS free tier using OpenTofu, ECS on EC2, and GitHub Actions. Console players (Xbox, Switch, PlayStation) can use a custom server list in Minecraft Bedrock's Featured Servers screen by pointing their network DNS at this server.

## Architecture

```
Internet
  │
  ├── 19132/UDP ──► ECS Service: bedrockconnect (pugmatt/bedrock-connect)
  └──    53/UDP ──► ECS Service: bind9 (custom image — redirects featured server hostnames)
                        │
                    EC2 t2.micro  ← ECS-optimized AMI, host network mode
                    Elastic IP    ← static public IP
                    Public Subnet → Internet Gateway
                    VPC (10.0.0.0/16)
```

**AWS resources (all free-tier eligible):**
- VPC + public subnet + internet gateway
- Elastic IP (static address for DNS stability)
- EC2 t2.micro running the ECS agent
- ECS Cluster with two services: `bedrockconnect` and `bind9`
- ECR repository for the custom bind9 image
- CloudWatch Log Groups (7-day retention) for both services
- S3 + DynamoDB for OpenTofu remote state

**bind9 self-discovery:** The custom bind9 image queries the EC2 instance metadata service at startup to get the public IP, then generates zone files dynamically. No config rebuild needed when the IP changes.

**GitHub Actions security:** Uses OIDC federation — no long-lived AWS credentials stored as secrets.

## Repository Structure

```
.
├── tofu/
│   ├── bootstrap/       # One-time setup: S3 state bucket, DynamoDB, GitHub OIDC role
│   ├── modules/
│   │   ├── networking/  # VPC, subnet, IGW, route table, Elastic IP
│   │   └── ecs-cluster/ # EC2, ECS, ECR, IAM, CloudWatch
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf
├── bind9/
│   ├── Dockerfile
│   └── entrypoint.sh    # Generates bind9 zone files from EC2 metadata at startup
└── .github/workflows/
    ├── tofu-plan.yml    # Posts plan output as PR comment
    └── tofu-apply.yml   # Builds bind9 image → pushes to ECR → tofu apply
```

## Setup

### Prerequisites

- AWS account (free tier)
- OpenTofu ≥ 1.6
- AWS CLI configured (`aws configure`)

### 1. Bootstrap (one-time)

Creates the S3 state bucket, DynamoDB lock table, and GitHub OIDC IAM role:

```bash
cd tofu/bootstrap
tofu init
tofu apply
```

Note the outputs — you'll need `state_bucket_name` and `github_actions_role_arn`.

### 2. Configure the backend

Edit `tofu/backend.tf` and set `bucket` to the value from step 1.

### 3. Add the GitHub secret

In your GitHub repo → Settings → Secrets → Actions, add:

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | `github_actions_role_arn` output from bootstrap |

### 4. Deploy

Push to `main`. GitHub Actions will:
1. Create the ECR repository
2. Build and push the bind9 image
3. Apply the full OpenTofu configuration

### 5. Configure players

After deploy, the public IP appears in the Actions log (`tofu output public_ip`).

**Network-wide (consoles):** Set your router's primary DNS to the server's Elastic IP. Minecraft Bedrock → Featured Servers → you'll see the BedrockConnect server list.

**Single PC:** Change your network adapter's DNS to the Elastic IP temporarily.

## CI/CD

| Trigger | Action |
|---------|--------|
| Pull request | `tofu fmt`, `tofu validate`, `tofu plan` → plan posted as PR comment |
| Push to `main` | Build bind9 image → push to ECR → `tofu apply` |

## Domains Redirected by bind9

| Featured Server | Hostname Redirected |
|----------------|---------------------|
| The Hive | `geo.hivebedrock.network` |
| Mineville | `play.inpvp.net` |
| Lifeboat | `mco.lbsg.net` |
| Galaxite | `play.galaxite.net` |
| Enchanted Dragons | `play.enchanted.gg` |
