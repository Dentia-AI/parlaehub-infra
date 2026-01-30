output "database_url" {
  description = "Database connection URL"
  value       = local.database_url
  sensitive   = true
}

output "database_name" {
  description = "Name of the created database"
  value       = var.database_name
}

output "db_host" {
  description = "Database host"
  value       = var.aurora_endpoint
}

output "db_username" {
  description = "Database username"
  value       = var.db_username
}

output "ssm_parameter_database_url" {
  description = "SSM parameter name for DATABASE_URL"
  value       = aws_ssm_parameter.database_url.name
}

