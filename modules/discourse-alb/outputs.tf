output "target_group_arn" {
  description = "ARN of blue target group"
  value       = aws_lb_target_group.discourse.arn
}

output "target_group_name" {
  description = "Name of blue target group"
  value       = aws_lb_target_group.discourse.name
}

output "target_group_green_arn" {
  description = "ARN of green target group (if enabled)"
  value       = var.enable_blue_green ? aws_lb_target_group.discourse_green[0].arn : ""
}

output "target_group_green_name" {
  description = "Name of green target group (if enabled)"
  value       = var.enable_blue_green ? aws_lb_target_group.discourse_green[0].name : ""
}

output "listener_rule_arn" {
  description = "ARN of ALB listener rule"
  value       = aws_lb_listener_rule.discourse.arn
}

output "discourse_urls" {
  description = "List of Discourse URLs"
  value       = [for hostname in var.discourse_hostnames : "https://${hostname}"]
}

