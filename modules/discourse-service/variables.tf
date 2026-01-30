variable "project_id" {
  description = "Project identifier (e.g., parlaehub-prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# ECS Configuration
variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group for ECS tasks"
  type        = string
}

# Networking
variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP to ECS tasks"
  type        = bool
  default     = true
}

# Task Configuration
variable "task_cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Fargate task memory (MB)"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# Container Image
variable "ecr_repository_url" {
  description = "ECR repository URL for Discourse image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

# Application Configuration
variable "primary_hostname" {
  description = "Primary hostname for Discourse"
  type        = string
}

variable "cdn_url" {
  description = "CDN URL (optional)"
  type        = string
  default     = ""
}

variable "discourse_connect_provider_url" {
  description = "URL of the Dentia app DiscourseConnect endpoint"
  type        = string
}

variable "additional_environment_variables" {
  description = "Additional environment variables"
  type        = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "enable_container_health_check" {
  description = "Enable ECS container-level health check"
  type        = bool
  default     = false
}

# SSM Parameters
variable "ssm_prefix" {
  description = "SSM parameter prefix"
  type        = string
}

# Load Balancer
variable "target_group_arn" {
  description = "Target group ARN"
  type        = string
}

variable "target_group_name" {
  description = "Target group name"
  type        = string
}

variable "alb_name" {
  description = "ALB name (for CloudWatch alarms)"
  type        = string
}

variable "alb_target_group_resource_label" {
  description = "ALB target group resource label for request count scaling"
  type        = string
  default     = ""
}

# Blue/Green Deployment
variable "enable_blue_green" {
  description = "Enable blue/green deployment with CodeDeploy"
  type        = bool
  default     = false
}

# Auto-scaling
variable "autoscaling_min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 8
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for scaling"
  type        = number
  default     = 65
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for scaling"
  type        = number
  default     = 75
}

variable "request_count_target_value" {
  description = "Target request count per target for scaling"
  type        = number
  default     = 1000
}

variable "enable_request_count_scaling" {
  description = "Enable request count-based auto-scaling"
  type        = bool
  default     = false
}

variable "scale_in_cooldown" {
  description = "Cooldown period (seconds) between scale-in activities"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Cooldown period (seconds) between scale-out activities"
  type        = number
  default     = 60
}

# Monitoring
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "alarm_actions" {
  description = "SNS topic ARNs for alarm notifications"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
