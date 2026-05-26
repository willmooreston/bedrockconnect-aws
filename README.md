(this is a work in progress)

# BedrockConnect on AWS

Deploys [BedrockConnect](https://github.com/Pugmatt/BedrockConnect) on AWS free tier using OpenTofu and ECS on EC2. Console players (Xbox, Switch, PlayStation) can use a custom server list in Minecraft Bedrock's Featured Servers screen by pointing their network DNS at this server.

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
- S3 for OpenTofu remote state (native S3 locking, no DynamoDB needed)

**bind9 self-discovery:** The custom bind9 image queries the EC2 instance metadata service at startup to get the public IP, then generates zone files dynamically. No config rebuild needed when the IP changes.

**IP allowlisting:** Access to ports 19132 and 53 is restricted by security group. Allowed CIDRs are set in `tofu/terraform.tfvars` (gitignored — copy from `example.tfvars`).

## Repository Structure

```
.
├── tofu/
│   ├── bootstrap/       # One-time setup: S3 state bucket, GitHub OIDC role
│   ├── modules/
│   │   ├── networking/  # VPC, subnet, IGW, route table, Elastic IP
│   │   └── ecs-cluster/ # EC2, ECS, ECR, IAM, CloudWatch
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── terraform.tfvars        # gitignored — your allowed CIDRs go here
│   └── example.tfvars          # committed template for terraform.tfvars
├── bind9/
│   ├── Dockerfile
│   └── entrypoint.sh           # Generates bind9 zone files from EC2 metadata at startup
└── .github/workflows/
    ├── tofu-plan.yml.disabled   # Posts plan output as PR comment (re-enable when ready)
    └── tofu-apply.yml.disabled  # Builds bind9 image → pushes to ECR → tofu apply
```

## Setup

### Prerequisites

- AWS account (free tier)
- OpenTofu ≥ 1.6
- AWS CLI configured (`aws configure`)

### 1. Bootstrap (one-time)

Creates the S3 state bucket and GitHub OIDC IAM role:

```bash
cd tofu/bootstrap
tofu init
tofu apply
```

Note the `state_bucket_name` output — confirm it matches `tofu/backend.tf`.

### 2. Configure allowed CIDRs

Copy `tofu/example.tfvars` to `tofu/terraform.tfvars` and add your IP(s):

```hcl
allowed_ipv6_cidrs = ["your:ipv6:address/128"]
# allowed_ipv4_cidrs = ["203.0.113.1/32"]
```

### 3. Deploy

```bash
cd tofu
tofu init
tofu apply
```

### 4. Configure players

After deploy, get the public IP:

```bash
tofu output public_ip
```

**Network-wide (consoles):** Set your router's primary DNS to the server's Elastic IP. Minecraft Bedrock → Featured Servers → you'll see the BedrockConnect server list.

**Single PC:** Change your network adapter's DNS to the Elastic IP temporarily.

## CI/CD

GitHub Actions workflows exist but are currently disabled (`.github/workflows/*.disabled`). When re-enabled:

| Trigger | Action |
|---------|--------|
| Pull request | `tofu fmt`, `tofu validate`, `tofu plan` → plan posted as PR comment |
| Push to `main` | Build bind9 image → push to ECR → `tofu apply` |

To re-enable, rename the workflow files to `.yml` and add `AWS_ROLE_ARN` (from bootstrap output) as a repo Actions secret. Pass allowed CIDRs via a `TF_VAR_allowed_ipv6_cidrs` secret.

## Domains Redirected by bind9

| Featured Server | Hostname Redirected |
|----------------|---------------------|
| The Hive | `geo.hivebedrock.network` |
| Mineville | `play.inpvp.net` |
| Lifeboat | `mco.lbsg.net` |
| Galaxite | `play.galaxite.net` |
| Enchanted Dragons | `play.enchanted.gg` |
