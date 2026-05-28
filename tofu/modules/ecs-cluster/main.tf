data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "bedrockconnect" {
  name   = "${var.project}-sg"
  vpc_id = var.vpc_id

  ingress {
    description      = "BedrockConnect Bedrock protocol"
    from_port        = 19132
    to_port          = 19132
    protocol         = "udp"
    cidr_blocks      = var.allowed_ipv4_cidrs
    ipv6_cidr_blocks = var.allowed_ipv6_cidrs
  }

  dynamic "ingress" {
    for_each = var.use_bind9 ? [1] : []
    content {
      description      = "bind9 DNS"
      from_port        = 53
      to_port          = 53
      protocol         = "udp"
      cidr_blocks      = var.allowed_ipv4_cidrs
      ipv6_cidr_blocks = var.allowed_ipv6_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg" }
}

# ── IAM: EC2 instance role ────────────────────────────────────────────────────

resource "aws_iam_role" "ec2_instance" {
  name = "${var.project}-ec2-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_for_ec2" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance" {
  name = "${var.project}-ec2-instance"
  role = aws_iam_role.ec2_instance.name
}

# ── IAM: ECS task execution role ─────────────────────────────────────────────

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecr_pull" {
  name = "${var.project}-ecr-pull"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
      ]
      Resource = "*"
    }]
  })
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "bedrockconnect" {
  ami                    = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = "t2.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bedrockconnect.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance.name

  user_data = <<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
    yum install -y bind-utils
  EOF

  tags = { Name = "${var.project}-ec2" }
}

resource "aws_eip_association" "bedrockconnect" {
  instance_id   = aws_instance.bedrockconnect.id
  allocation_id = var.eip_allocation_id
}

# ── ECR ───────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "bind9" {
  count                = var.use_bind9 ? 1 : 0
  name                 = "${var.project}-bind9"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "bind9" {
  count      = var.use_bind9 ? 1 : 0
  repository = aws_ecr_repository.bind9[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = var.project
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "bedrockconnect" {
  name              = "/ecs/${var.project}/bedrockconnect"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "bind9" {
  count             = var.use_bind9 ? 1 : 0
  name              = "/ecs/${var.project}/bind9"
  retention_in_days = 7
}

# ── ECS Task: bedrockconnect ──────────────────────────────────────────────────

resource "aws_ecs_task_definition" "bedrockconnect" {
  family                = "${var.project}-bedrockconnect"
  network_mode          = "host"
  execution_role_arn    = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name              = "bedrockconnect"
    image             = var.bedrockconnect_image
    memoryReservation = 512
    essential         = true

    portMappings = [{
      containerPort = 19132
      hostPort      = 19132
      protocol      = "udp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.bedrockconnect.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "bedrockconnect" {
  name                               = "bedrockconnect"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.bedrockconnect.arn
  desired_count                      = 1
  availability_zone_rebalancing      = "DISABLED"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_eip_association.bedrockconnect]
}

# ── ECS Task: bind9 ───────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "bind9" {
  count                 = var.use_bind9 ? 1 : 0
  family                = "${var.project}-bind9"
  network_mode          = "host"
  execution_role_arn    = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name              = "bind9"
    image             = var.bind9_image_uri
    memoryReservation = 128
    essential         = true

    portMappings = [{
      containerPort = 53
      hostPort      = 53
      protocol      = "udp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.bind9[0].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "bind9" {
  count                              = var.use_bind9 ? 1 : 0
  name                               = "bind9"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.bind9[0].arn
  desired_count                      = 1
  availability_zone_rebalancing      = "DISABLED"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # host networking means two tasks can't hold port 53 simultaneously;
  # stop the old task before starting the new one
  depends_on = [aws_eip_association.bedrockconnect]
}
