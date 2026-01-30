variable "project_id" {
  description = "Project identifier (e.g., parlaehub-prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of ECS task role"
  type        = string
}

variable "allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "cloudfront_oai_arn" {
  description = "CloudFront Origin Access Identity ARN (optional)"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "create_backup_bucket" {
  description = "Create separate bucket for backups"
  type        = bool
  default     = true
}

variable "ssm_prefix" {
  description = "SSM parameter prefix"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

