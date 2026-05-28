output "ecr_repository_url" {
  value = var.use_bind9 ? aws_ecr_repository.bind9[0].repository_url : null
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}
