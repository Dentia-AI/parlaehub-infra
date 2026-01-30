###############################################
# Discourse ALB Module
# ALB target group and listener rules
###############################################

# Target group for Discourse
resource "aws_lb_target_group" "discourse" {
  name        = "${var.project_id}-hub-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_id}-hub-tg"
  })
}

# Optional: Blue/Green deployment - create green target group
resource "aws_lb_target_group" "discourse_green" {
  count = var.enable_blue_green ? 1 : 0
  
  name        = "${var.project_id}-hub-tg-grn"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_id}-hub-tg-grn"
  })
}

# Get existing ALB listener
data "aws_lb_listener" "https" {
  load_balancer_arn = var.alb_arn
  port              = 443
}

# Listener rule for Discourse hostnames
resource "aws_lb_listener_rule" "discourse" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.discourse.arn
  }

  condition {
    host_header {
      values = var.discourse_hostnames
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      action  # For blue/green deployment, action is modified externally
    ]
  }
}

# NOTE: DNS records are now managed by dentia-infra (in dentia-infra/infra/ecs/locals.tf)
# This ensures records are created in the correct hosted zones for each domain:
#   - hub.dentiaapp.com → dentiaapp.com zone
#   - hub.dentia.co → dentia.co zone
#   - hub.dentia.app → dentia.app zone
#   - hub.dentia.ca → dentia.ca zone
#
# The old resource "aws_route53_record" "discourse" has been removed to prevent
# duplicate/incorrect records being created in the wrong zones.
