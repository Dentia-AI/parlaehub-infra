output "discourse_urls" {
  description = "Discourse URLs"
  value       = module.discourse_alb.discourse_urls
}

output "ecr_repository_url" {
  description = "ECR repository URL for Discourse"
  value       = aws_ecr_repository.discourse.repository_url
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.discourse_service.service_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = local.ecs_cluster_name
}

output "s3_uploads_bucket" {
  description = "S3 bucket for uploads"
  value       = module.discourse_storage.uploads_bucket_id
}

output "s3_backups_bucket" {
  description = "S3 bucket for backups"
  value       = module.discourse_storage.backups_bucket_id
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.discourse_redis.redis_endpoint
}

output "database_name" {
  description = "Database name"
  value       = module.discourse_database.database_name
}

output "cognito_client_id" {
  description = "Cognito client ID for Discourse"
  value       = aws_cognito_user_pool_client.discourse.id
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.discourse_service.log_group_name
}

