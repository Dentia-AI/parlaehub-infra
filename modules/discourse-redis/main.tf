###############################################
# Discourse Redis Module
# ElastiCache Redis with auto-scaling
###############################################

# Redis subnet group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_id}-redis-subnet"
  subnet_ids = var.private_subnet_ids
  
  tags = var.tags
}

# Redis security group
resource "aws_security_group" "redis" {
  name        = "${var.project_id}-redis-sg"
  description = "Security group for Discourse Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_id}-redis-sg"
  })
}

# Redis parameter group
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.project_id}-redis-params"
  family = "redis7"

  # Discourse-optimized settings
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = var.tags
}

# Redis replication group (cluster mode disabled for simplicity)
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_id}-redis"
  description          = "Redis for Discourse ${var.environment}"
  
  engine               = "redis"
  engine_version       = "7.1"
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  node_type            = var.node_type
  num_cache_clusters   = var.environment == "production" ? var.num_replicas : 1
  
  # Auto-failover requires at least 2 nodes
  automatic_failover_enabled = var.environment == "production" ? var.num_replicas > 1 : false
  multi_az_enabled          = var.environment == "production" ? var.num_replicas > 1 : false
  
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false  # Discourse doesn't support TLS for Redis by default
  
  # Maintenance and backups
  maintenance_window       = var.maintenance_window
  snapshot_window          = var.snapshot_window
  snapshot_retention_limit = var.environment == "production" ? 5 : 1
  
  # Auto minor version upgrade
  auto_minor_version_upgrade = true
  
  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = false  # Set to true for production via protect_resources
  }

  tags = var.tags
}

# Store Redis connection info in SSM
resource "aws_ssm_parameter" "redis_url" {
  name        = "${var.ssm_prefix}/REDIS_URL"
  description = "Redis connection URL"
  type        = "String"
  value       = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
  
  tags = var.tags
}

resource "aws_ssm_parameter" "redis_host" {
  name        = "${var.ssm_prefix}/REDIS_HOST"
  description = "Redis host"
  type        = "String"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  
  tags = var.tags
}

resource "aws_ssm_parameter" "redis_port" {
  name        = "${var.ssm_prefix}/REDIS_PORT"
  description = "Redis port"
  type        = "String"
  value       = "6379"
  
  tags = var.tags
}

