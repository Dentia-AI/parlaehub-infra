variable "project_id" {
  description = "Project identifier (e.g., parlaehub-prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "alb_arn" {
  description = "ARN of shared ALB"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of shared ALB"
  type        = string
}

variable "alb_zone_id" {
  description = "Zone ID of shared ALB"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 zone ID for DNS records"
  type        = string
}

variable "discourse_hostnames" {
  description = "List of hostnames for Discourse (e.g., hub.dentiaapp.com)"
  type        = list(string)
}

variable "listener_rule_priority" {
  description = "ALB listener rule priority (must be unique)"
  type        = number
  default     = 100
}

variable "deregistration_delay" {
  description = "Time to wait before deregistering targets (seconds)"
  type        = number
  default     = 30
}

variable "enable_blue_green" {
  description = "Create green target group for blue/green deployment"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Path used by ALB health checks"
  type        = string
  default     = "/srv/status"
}

variable "health_check_matcher" {
  description = "HTTP codes considered healthy by ALB health checks"
  type        = string
  default     = "200-399"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
