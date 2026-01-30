output "service_id" {
  description = "ECS service ID"
  value       = aws_ecs_service.discourse.id
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.discourse.name
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.discourse.arn
}

output "task_definition_family" {
  description = "Task definition family"
  value       = aws_ecs_task_definition.discourse.family
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.discourse.name
}

output "autoscaling_target_id" {
  description = "Auto-scaling target ID"
  value       = aws_appautoscaling_target.discourse.id
}

