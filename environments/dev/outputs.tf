output "discourse_url" {
  description = "Discourse dev URL"
  value       = "https://${local.discourse_hostname}"
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.discourse_service.service_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = local.ecs_cluster_name
}

output "aurora_endpoint" {
  description = "Aurora endpoint"
  value       = aws_rds_cluster.dev_aurora.endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.discourse_redis.redis_endpoint
}

output "s3_uploads_bucket" {
  description = "S3 bucket for uploads"
  value       = module.discourse_storage.uploads_bucket_id
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.discourse_service.log_group_name
}

output "environment_id" {
  description = "Unique environment identifier"
  value       = local.project_id
}

