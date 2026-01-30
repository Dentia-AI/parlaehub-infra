output "uploads_bucket_id" {
  description = "S3 bucket ID for uploads"
  value       = aws_s3_bucket.uploads.id
}

output "uploads_bucket_arn" {
  description = "S3 bucket ARN for uploads"
  value       = aws_s3_bucket.uploads.arn
}

output "uploads_bucket_domain" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.uploads.bucket_domain_name
}

output "backups_bucket_id" {
  description = "S3 bucket ID for backups"
  value       = var.create_backup_bucket ? aws_s3_bucket.backups[0].id : ""
}

output "backups_bucket_arn" {
  description = "S3 bucket ARN for backups"
  value       = var.create_backup_bucket ? aws_s3_bucket.backups[0].arn : ""
}

