###############################################
# ParlaeHub Production Environment
# Self-hosted Discourse community forum
###############################################

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "parlaehub-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-2"
    profile        = "dentia"
    encrypt        = true
    dynamodb_table = "parlaehub-terraform-locks"
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

###############################################
# Data Sources - Read from Dentia Infrastructure
###############################################

# Dentia infrastructure state (using local backend)
data "terraform_remote_state" "dentia" {
  backend = "local"
  
  config = {
    path = "../../../dentia-infra/infra/ecs/terraform.tfstate"
  }
}

# Get ALB details
data "aws_lb" "dentia_alb" {
  arn = data.terraform_remote_state.dentia.outputs.alb_arn
}

# Get Route53 zone
data "aws_route53_zone" "primary" {
  name = var.domain
}

###############################################
# Local Variables
###############################################

locals {
  project_name = "parlaehub"
  environment  = "production"
  project_id   = "${local.project_name}-${local.environment}"
  
  ssm_prefix = "/parlaehub/production"
  
  tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
  
  # Shared resources from Dentia
  vpc_id                = data.terraform_remote_state.dentia.outputs.vpc_id
  private_subnet_ids    = data.terraform_remote_state.dentia.outputs.private_subnet_ids
  public_subnet_ids     = data.terraform_remote_state.dentia.outputs.public_subnet_ids
  ecs_cluster_id        = data.terraform_remote_state.dentia.outputs.ecs_cluster_id
  ecs_cluster_name      = data.terraform_remote_state.dentia.outputs.ecs_cluster_name
  ecs_security_group_id = data.terraform_remote_state.dentia.outputs.ecs_sg_id
  db_security_group_id  = data.terraform_remote_state.dentia.outputs.db_sg_id
  alb_arn               = data.terraform_remote_state.dentia.outputs.alb_arn
  alb_dns_name          = data.terraform_remote_state.dentia.outputs.alb_dns_name
  alb_zone_id           = data.aws_lb.dentia_alb.zone_id
  cognito_user_pool_id  = data.terraform_remote_state.dentia.outputs.cognito_user_pool_id
  cognito_domain        = data.terraform_remote_state.dentia.outputs.cognito_domain
  aurora_cluster_id     = data.terraform_remote_state.dentia.outputs.aurora_cluster_id
  aurora_endpoint       = data.terraform_remote_state.dentia.outputs.aurora_endpoint
  
  # Discourse hostnames
  discourse_hostnames = [
    "hub.${var.domain}",
    "hub.dentia.co",
    "hub.dentia.app",
    "hub.dentia.ca",
  ]
}

###############################################
# ECR Repository for Discourse
###############################################

resource "aws_ecr_repository" "discourse" {
  name                 = "parlaehub/discourse"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "discourse" {
  repository = aws_ecr_repository.discourse.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

###############################################
# IAM Roles for ECS
###############################################

# ECS Task Execution Role (for pulling images, getting secrets)
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.project_id}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for SSM parameters
resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name = "${local.project_id}-ssm-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter${local.ssm_prefix}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECS Task Role (for application permissions)
resource "aws_iam_role" "ecs_task" {
  name = "${local.project_id}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# S3 access policy
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${local.project_id}-s3-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.discourse_storage.uploads_bucket_arn,
          "${module.discourse_storage.uploads_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ECS Exec policy (for debugging)
resource "aws_iam_role_policy" "ecs_exec" {
  name = "${local.project_id}-ecs-exec"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################
# Security Group Rules
###############################################

# Allow ECS tasks to access Aurora
resource "aws_security_group_rule" "ecs_to_aurora" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = local.ecs_security_group_id
  security_group_id        = local.db_security_group_id
  description              = "Allow ParlaeHub ECS tasks to access Aurora"
  
  lifecycle {
    ignore_changes = all
  }
}

###############################################
# Cognito App Client for Discourse
###############################################

resource "aws_cognito_user_pool_client" "discourse" {
  name         = "parlaehub-${local.environment}"
  user_pool_id = local.cognito_user_pool_id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  supported_identity_providers         = var.enable_google_identity_provider ? ["COGNITO", "Google"] : ["COGNITO"]

  callback_urls = [
    for hostname in local.discourse_hostnames :
    "https://${hostname}/auth/oauth2_basic/callback"
  ]

  logout_urls = [
    for hostname in local.discourse_hostnames :
    "https://${hostname}"
  ]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# Store Cognito details in SSM
resource "aws_ssm_parameter" "cognito_client_id" {
  name      = "${local.ssm_prefix}/COGNITO_CLIENT_ID"
  type      = "String"
  value     = aws_cognito_user_pool_client.discourse.id
  overwrite = true
  tags      = local.tags
}

resource "aws_ssm_parameter" "cognito_client_secret" {
  name      = "${local.ssm_prefix}/COGNITO_CLIENT_SECRET"
  type      = "SecureString"
  value     = aws_cognito_user_pool_client.discourse.client_secret
  overwrite = true
  tags      = local.tags
}

resource "aws_ssm_parameter" "cognito_issuer" {
  name      = "${local.ssm_prefix}/COGNITO_ISSUER"
  type      = "String"
  value     = "https://cognito-idp.${var.region}.amazonaws.com/${local.cognito_user_pool_id}"
  overwrite = true
  tags      = local.tags
}

resource "aws_ssm_parameter" "cognito_domain" {
  name      = "${local.ssm_prefix}/COGNITO_DOMAIN"
  type      = "String"
  value     = local.cognito_domain
  overwrite = true
  tags      = local.tags
}

resource "aws_ssm_parameter" "discourse_connect_secret" {
  name      = "${local.ssm_prefix}/DISCOURSE_CONNECT_SECRET"
  type      = "SecureString"
  value     = var.discourse_connect_secret
  overwrite = true
  tags      = local.tags
}

# Aurora master password for automatic database setup
resource "aws_ssm_parameter" "aurora_master_password" {
  name      = "${local.ssm_prefix}/AURORA_MASTER_PASSWORD"
  type      = "SecureString"
  value     = var.aurora_master_password
  overwrite = true
  tags      = local.tags
}

###############################################
# Discourse Modules
###############################################

# Database
module "discourse_database" {
  source = "../../modules/discourse-database"

  aurora_cluster_id       = local.aurora_cluster_id
  aurora_endpoint         = local.aurora_endpoint
  aurora_master_username  = var.aurora_master_username
  aurora_master_password  = var.aurora_master_password
  database_name           = "discourse_production"
  db_username             = "discourse_user"
  db_password             = var.discourse_db_password
  ssm_prefix              = local.ssm_prefix
  
  # Disable automatic database creation (will be done manually via bastion)
  create_database         = false
  create_user             = false
  
  tags = local.tags
}

# Redis - optimized for minimal cost with single-node setup
module "discourse_redis" {
  source = "../../modules/discourse-redis"

  project_id             = local.project_id
  environment            = local.environment
  vpc_id                 = local.vpc_id
  private_subnet_ids     = local.private_subnet_ids
  ecs_security_group_id  = local.ecs_security_group_id
  node_type              = "cache.t4g.micro"  # Smallest instance for cost optimization
  num_replicas           = 1  # Single node to minimize cost
  ssm_prefix             = local.ssm_prefix
  
  tags = local.tags
}

# Storage
module "discourse_storage" {
  source = "../../modules/discourse-storage"

  project_id             = local.project_id
  region                 = var.region
  ecs_task_role_arn      = aws_iam_role.ecs_task.arn
  allowed_origins        = local.discourse_hostnames
  enable_versioning      = true
  create_backup_bucket   = true
  ssm_prefix             = local.ssm_prefix
  
  tags = local.tags
}

# ALB Integration
module "discourse_alb" {
  source = "../../modules/discourse-alb"

  project_id           = local.project_id
  vpc_id               = local.vpc_id
  alb_arn              = local.alb_arn
  alb_dns_name         = local.alb_dns_name
  alb_zone_id          = local.alb_zone_id
  route53_zone_id      = data.aws_route53_zone.primary.zone_id
  discourse_hostnames  = local.discourse_hostnames
  listener_rule_priority = 100
  enable_blue_green    = true
  health_check_path    = "/srv/status"
  health_check_matcher = "200"
  
  tags = local.tags
}

# ECS Service
module "discourse_service" {
  source = "../../modules/discourse-service"

  project_id               = local.project_id
  region                   = var.region
  environment              = local.environment
  ecs_cluster_id           = local.ecs_cluster_id
  ecs_cluster_name         = local.ecs_cluster_name
  ecs_execution_role_arn   = aws_iam_role.ecs_task_execution.arn
  ecs_task_role_arn        = aws_iam_role.ecs_task.arn
  ecs_security_group_id    = local.ecs_security_group_id
  subnet_ids               = local.public_subnet_ids
  assign_public_ip         = true
  
  task_cpu                 = 2048  # 2 vCPU for faster asset compilation
  task_memory              = 4096  # 4GB for asset compilation (can reduce to 2GB after first boot)
  desired_count            = 1  # Start with one task
  
  ecr_repository_url       = aws_ecr_repository.discourse.repository_url
  image_tag                = var.discourse_image_tag
  
  primary_hostname         = local.discourse_hostnames[0]
  cdn_url                  = ""
  ssm_prefix               = local.ssm_prefix
  discourse_connect_provider_url = "https://app.${var.domain}/sso/discourse"
  
  target_group_arn         = module.discourse_alb.target_group_arn
  target_group_name        = module.discourse_alb.target_group_name
  alb_name                 = split("/", local.alb_arn)[1]
  
  enable_blue_green        = false  # Disable for simpler deployments and lower cost
  
  autoscaling_min_capacity = 1  # Can't scale to 0 with Fargate, but will stay at 1 on no load
  autoscaling_max_capacity = 4  # Reduced max capacity
  cpu_target_value         = 70  # Scale up slightly later
  memory_target_value      = 80  # Scale up slightly later
  enable_container_health_check = false
  
  log_retention_days       = 30
  alarm_actions            = []
  
  tags = local.tags
  
  depends_on = [
    module.discourse_database,
    module.discourse_redis,
    module.discourse_storage,
    module.discourse_alb
  ]
}
