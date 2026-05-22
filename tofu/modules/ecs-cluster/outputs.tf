output "ecr_repository_url" {
  value = aws_ecr_repository.bind9.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}
