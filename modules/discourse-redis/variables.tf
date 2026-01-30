variable "project_id" {
  description = "Project identifier (e.g., parlaehub-prod)"
  type        = string
}

variable "environment" {
  description = "Environment name (production, staging, dev)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Redis"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID of ECS tasks"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_replicas" {
  description = "Number of cache clusters (primary + replicas)"
  type        = number
  default     = 2
}

variable "maintenance_window" {
  description = "Maintenance window (UTC)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "snapshot_window" {
  description = "Snapshot window (UTC)"
  type        = string
  default     = "03:00-04:00"
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

