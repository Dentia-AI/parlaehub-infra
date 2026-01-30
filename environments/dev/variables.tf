variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "dentia"
}

variable "domain" {
  description = "Primary domain for ParlaeHub"
  type        = string
  default     = "dentiaapp.com"
}

variable "branch_name" {
  description = "Git branch name (used for environment suffix)"
  type        = string
  default     = "dev"
}

variable "aurora_dev_password" {
  description = "Password for dev Aurora cluster"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL for Discourse image"
  type        = string
}

variable "discourse_image_tag" {
  description = "Discourse Docker image tag"
  type        = string
  default     = "latest"
}

variable "listener_priority_offset" {
  description = "Offset for ALB listener rule priority (to avoid conflicts)"
  type        = number
  default     = 0
}

variable "enable_google_identity_provider" {
  description = "Enable Google as an identity provider for the dev Cognito client"
  type        = bool
  default     = true
}

variable "discourse_connect_secret" {
  description = "Shared DiscourseConnect secret used between Dentia app and Discourse"
  type        = string
  sensitive   = true
}
