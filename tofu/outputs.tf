output "public_ip" {
  value       = module.networking.public_ip
  description = "Elastic IP of the BedrockConnect server — point your DNS here"
}

output "ecr_repository_url" {
  value       = module.ecs_cluster.ecr_repository_url
  description = "ECR URL for the custom bind9 image"
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.ecs_cluster_name
}
