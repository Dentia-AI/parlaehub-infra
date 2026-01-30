variable "region" {
  description = "AWS region"
  type        = string
  default     = "v20251112-1246"
}

variable "profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "v20251112-1246"
}

variable "domain" {
  description = "Primary domain for ParlaeHub"
  type        = string
  default     = "v20251112-1246"
}

variable "aurora_master_username" {
  description = "Aurora master username"
  type        = string
  default     = "v20251112-1246"
}

variable "aurora_master_password" {
  description = "Aurora master password"
  type        = string
  sensitive   = true
}

variable "discourse_db_password" {
  description = "Password for Discourse database user"
  type        = string
  sensitive   = true
}

variable "enable_google_identity_provider" {
  description = "Enable Google as an identity provider for Cognito app client"
  type        = bool
  default     = true
}
variable "discourse_image_tag" {
  description = "Discourse Docker image tag"
  type        = string
  default     = "v20251112-1246"  # No flash fix (CSS + aggressive interceptors)
}

variable "discourse_connect_secret" {
  description = "Shared DiscourseConnect secret used by the Dentia app and Discourse"
  type        = string
  sensitive   = true
}
