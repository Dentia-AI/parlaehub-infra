variable "aurora_cluster_id" {
  description = "ID of the shared Aurora cluster"
  type        = string
}

variable "aurora_endpoint" {
  description = "Endpoint of the shared Aurora cluster"
  type        = string
}

variable "aurora_master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  default     = "dentia_admin"
}

variable "aurora_master_password" {
  description = "Master password for Aurora cluster"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "discourse"
}

variable "db_username" {
  description = "Database user for Discourse"
  type        = string
  default     = "discourse_user"
}

variable "db_password" {
  description = "Password for Discourse database user"
  type        = string
  sensitive   = true
}

variable "create_database" {
  description = "Whether to create the database"
  type        = bool
  default     = true
}

variable "create_user" {
  description = "Whether to create the database user"
  type        = bool
  default     = true
}

variable "ssm_prefix" {
  description = "SSM parameter prefix for storing secrets"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

