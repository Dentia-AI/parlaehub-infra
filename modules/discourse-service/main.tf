###############################################
# Discourse ECS Service Module
# ECS task definition, service, and auto-scaling
###############################################

# CloudWatch log group
resource "aws_cloudwatch_log_group" "discourse" {
  name              = "/ecs/${var.project_id}/discourse"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

# ECS Task Definition
resource "aws_ecs_task_definition" "discourse" {
  family                   = "${var.project_id}-discourse"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    merge({
      name      = "discourse"
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true
      
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.discourse.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "discourse"
        }
      }

      # Environment variables
      environment = concat(
        [
          { name = "RAILS_ENV", value = "production" },
          { name = "RACK_ENV", value = "production" },
          { name = "DISCOURSE_HOSTNAME", value = var.primary_hostname },
          { name = "DISCOURSE_CDN_URL", value = var.cdn_url },
          { name = "DISCOURSE_ENABLE_CORS", value = "true" },
          { name = "DISCOURSE_CORS_ORIGIN", value = "*" },
          { name = "DISCOURSE_SERVE_STATIC_ASSETS", value = "true" },
          { name = "DISCOURSE_DEVELOPER_EMAILS", value = "support@dentiaapp.com" },
          { name = "DISCOURSE_FORCE_HOSTNAME", value = var.primary_hostname },
          { name = "DISCOURSE_FORCE_SCHEME", value = "https" },
          { name = "DISCOURSE_CONNECT_PROVIDER_URL", value = var.discourse_connect_provider_url },
          { name = "SECRET_KEY_BASE", value = "e354ecfd1ce669f1bd674a5053fcfbcdf0e94787de200e3670b6cb5b16d760c9136e7446ded1c91fff13ecb17ea51e58c60345e520ae20a0b07c700a8fbb69a0" },
          { name = "AWS_REGION", value = var.region },
          # SMTP Configuration (MANDATORY for Discourse to work)
          { name = "DISCOURSE_SMTP_ADDRESS", value = "email-smtp.us-east-2.amazonaws.com" },
          { name = "DISCOURSE_SMTP_PORT", value = "587" },
          { name = "DISCOURSE_SMTP_ENABLE_START_TLS", value = "true" },
          { name = "DISCOURSE_SMTP_AUTHENTICATION", value = "login" },
          { name = "DISCOURSE_NOTIFICATION_EMAIL", value = "noreply@dentiaapp.com" },
        ],
        var.additional_environment_variables
      )

      # Secrets from SSM Parameter Store
      secrets = [
        { name = "DISCOURSE_DB_HOST", valueFrom = "${var.ssm_prefix}/DB_HOST" },
        { name = "DISCOURSE_DB_NAME", valueFrom = "${var.ssm_prefix}/DB_NAME" },
        { name = "DISCOURSE_DB_USERNAME", valueFrom = "${var.ssm_prefix}/DB_USERNAME" },
        { name = "DISCOURSE_DB_PASSWORD", valueFrom = "${var.ssm_prefix}/DB_PASSWORD" },
        { name = "DISCOURSE_REDIS_HOST", valueFrom = "${var.ssm_prefix}/REDIS_HOST" },
        { name = "DISCOURSE_S3_BUCKET", valueFrom = "${var.ssm_prefix}/S3_BUCKET" },
        { name = "DISCOURSE_S3_REGION", valueFrom = "${var.ssm_prefix}/S3_REGION" },
        { name = "COGNITO_CLIENT_ID", valueFrom = "${var.ssm_prefix}/COGNITO_CLIENT_ID" },
        { name = "COGNITO_CLIENT_SECRET", valueFrom = "${var.ssm_prefix}/COGNITO_CLIENT_SECRET" },
        { name = "COGNITO_ISSUER", valueFrom = "${var.ssm_prefix}/COGNITO_ISSUER" },
        { name = "COGNITO_DOMAIN", valueFrom = "${var.ssm_prefix}/COGNITO_DOMAIN" },
        { name = "DISCOURSE_CONNECT_SECRET", valueFrom = "${var.ssm_prefix}/DISCOURSE_CONNECT_SECRET" },
        { name = "AURORA_MASTER_PASSWORD", valueFrom = "${var.ssm_prefix}/AURORA_MASTER_PASSWORD" },
        { name = "DISCOURSE_SMTP_USER_NAME", valueFrom = "${var.ssm_prefix}/SMTP_USERNAME" },
        { name = "DISCOURSE_SMTP_PASSWORD", valueFrom = "${var.ssm_prefix}/SMTP_PASSWORD" },
      ]

      healthCheck = var.enable_container_health_check ? {
        command     = ["CMD-SHELL", "curl -s http://localhost:3000/srv/status > /dev/null || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 300
      } : null

      ulimits = [
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]
    }, var.enable_container_health_check ? {
      healthCheck = {
        command     = ["CMD-SHELL", "curl -s http://localhost:3000/srv/status > /dev/null || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 300
      }
    } : {})
  ])

  tags = var.tags
}

# ECS Service
resource "aws_ecs_service" "discourse" {
  name                               = "${var.project_id}-discourse"
  cluster                            = var.ecs_cluster_id
  task_definition                    = aws_ecs_task_definition.discourse.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 300  # 5 minutes for Discourse to fully start
  
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "discourse"
    container_port   = 3000
  }

  # Blue/Green deployment configuration
  deployment_controller {
    type = var.enable_blue_green ? "CODE_DEPLOY" : "ECS"
  }

  lifecycle {
    ignore_changes = [
       #task_definition,  # Managed by CI/CD
      desired_count,    # Managed by auto-scaling
    ]
  }

  tags = var.tags

  depends_on = [var.target_group_arn]
}

###############################################
# Auto-scaling Configuration
###############################################

# Auto-scaling target
resource "aws_appautoscaling_target" "discourse" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.discourse.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based auto-scaling
resource "aws_appautoscaling_policy" "discourse_cpu" {
  name               = "${var.project_id}-discourse-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.discourse.resource_id
  scalable_dimension = aws_appautoscaling_target.discourse.scalable_dimension
  service_namespace  = aws_appautoscaling_target.discourse.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
    
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# Memory-based auto-scaling
resource "aws_appautoscaling_policy" "discourse_memory" {
  name               = "${var.project_id}-discourse-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.discourse.resource_id
  scalable_dimension = aws_appautoscaling_target.discourse.scalable_dimension
  service_namespace  = aws_appautoscaling_target.discourse.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
    
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# Request count-based auto-scaling (ALB target tracking)
resource "aws_appautoscaling_policy" "discourse_request_count" {
  count = var.enable_request_count_scaling ? 1 : 0
  
  name               = "${var.project_id}-discourse-request-count-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.discourse.resource_id
  scalable_dimension = aws_appautoscaling_target.discourse.scalable_dimension
  service_namespace  = aws_appautoscaling_target.discourse.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.request_count_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
    
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.alb_target_group_resource_label
    }
  }
}

###############################################
# CloudWatch Alarms
###############################################

resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "${var.project_id}-discourse-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Discourse ECS service CPU utilization is too high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = aws_ecs_service.discourse.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "service_memory_high" {
  alarm_name          = "${var.project_id}-discourse-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Discourse ECS service memory utilization is too high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = aws_ecs_service.discourse.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_health_low" {
  alarm_name          = "${var.project_id}-discourse-target-health-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Discourse has fewer than 1 healthy target"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TargetGroup  = var.target_group_name
    LoadBalancer = var.alb_name
  }

  tags = var.tags
}
