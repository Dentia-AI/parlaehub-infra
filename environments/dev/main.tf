###############################################
# ParlaeHub Dev Environment (Ephemeral)
# Temporary environment for PR previews and testing
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
    key            = "dev/terraform.tfstate"  # Will be overridden by workspace
    region         = "us-east-2"
    profile        = "dentia"
    encrypt        = true
    dynamodb_table = "parlaehub-terraform-locks"
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = {
      Environment = "dev"
      Ephemeral   = "true"
      ManagedBy   = "Terraform"
    }
  }
}

###############################################
# Data Sources - Read from Dentia Infrastructure
###############################################

data "terraform_remote_state" "dentia" {
  backend = "s3"
  
  config = {
    bucket  = "dentia-terraform-state"
    key     = "ecs/terraform.tfstate"
    region  = "us-east-2"
    profile = "dentia"
  }
}

data "aws_lb" "dentia_alb" {
  arn = data.terraform_remote_state.dentia.outputs.alb_arn
}

data "aws_route53_zone" "primary" {
  name = var.domain
}

###############################################
# Local Variables
###############################################

locals {
  project_name = "parlaehub"
  environment  = "dev"
  branch_name  = var.branch_name != "" ? var.branch_name : "dev"
  env_suffix   = replace(local.branch_name, "/[^a-z0-9-]/", "-")
  project_id   = "${local.project_name}-${local.environment}-${local.env_suffix}"
  
  ssm_prefix = "/parlaehub/dev/${local.env_suffix}"
  
  tags = {
    Project     = local.project_name
    Environment = local.environment
    Branch      = local.branch_name
    Ephemeral   = "true"
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
  
  # Dev environment uses its own Aurora Serverless cluster for isolation
  discourse_hostname = "dev-${local.env_suffix}.hub.${var.domain}"
}

###############################################
# Production Protection Check
###############################################

resource "null_resource" "prevent_production_destroy" {
  provisioner "local-exec" {
    command = <<-EOT
      if [ "${local.environment}" = "production" ]; then
        echo "ERROR: Cannot use dev environment configuration for production!"
        exit 1
      fi
    EOT
  }
}

###############################################
# Dev Aurora Serverless v2 (Ephemeral)
###############################################

# Subnet group (use existing private subnets)
resource "aws_db_subnet_group" "dev_aurora" {
  name       = "${local.project_id}-aurora-subnet"
  subnet_ids = local.private_subnet_ids
  
  tags = local.tags
}

# Aurora cluster (Serverless v2)
resource "aws_rds_cluster" "dev_aurora" {
  cluster_identifier = "${local.project_id}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "15.12"
  engine_mode        = "provisioned"

  database_name             = "discourse_dev"
  master_username           = "discourse_admin"
  master_password           = var.aurora_dev_password
  db_subnet_group_name      = aws_db_subnet_group.dev_aurora.name
  vpc_security_group_ids    = [local.db_security_group_id]
  backup_retention_period   = 1
  storage_encrypted         = true
  skip_final_snapshot       = true  # Ephemeral - no final snapshot needed

  serverlessv2_scaling_configuration {
    min_capacity = 0.5  # Minimum for cost savings
    max_capacity = 2.0  # Low max for dev
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = false  # Can be destroyed
  }
}

# Aurora instance
resource "aws_rds_cluster_instance" "dev_aurora_instance" {
  identifier         = "${local.project_id}-aurora-instance"
  cluster_identifier = aws_rds_cluster.dev_aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.dev_aurora.engine
  engine_version     = aws_rds_cluster.dev_aurora.engine_version
}

# Store DB connection in SSM
resource "aws_ssm_parameter" "db_host" {
  name  = "${local.ssm_prefix}/DB_HOST"
  type  = "String"
  value = aws_rds_cluster.dev_aurora.endpoint
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.ssm_prefix}/DB_NAME"
  type  = "String"
  value = aws_rds_cluster.dev_aurora.database_name
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_username" {
  name  = "${local.ssm_prefix}/DB_USERNAME"
  type  = "String"
  value = aws_rds_cluster.dev_aurora.master_username
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_password" {
  name  = "${local.ssm_prefix}/DB_PASSWORD"
  type  = "SecureString"
  value = var.aurora_dev_password
  tags  = local.tags
}

###############################################
# IAM Roles for ECS
###############################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.project_id}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name = "${local.project_id}-ssm"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.region}:*:parameter${local.ssm_prefix}/*"
    }, {
      Effect = "Allow"
      Action = ["kms:Decrypt"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.project_id}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${local.project_id}-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        module.discourse_storage.uploads_bucket_arn,
        "${module.discourse_storage.uploads_bucket_arn}/*"
      ]
    }]
  })
}

###############################################
# Cognito App Client for Dev
###############################################

resource "aws_cognito_user_pool_client" "discourse_dev" {
  name         = "parlaehub-${local.environment}-${local.env_suffix}"
  user_pool_id = local.cognito_user_pool_id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  supported_identity_providers         = var.enable_google_identity_provider ? ["COGNITO", "Google"] : ["COGNITO"]

  callback_urls = ["https://${local.discourse_hostname}/auth/oauth2_basic/callback"]
  logout_urls   = ["https://${local.discourse_hostname}"]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_ssm_parameter" "cognito_client_id" {
  name  = "${local.ssm_prefix}/COGNITO_CLIENT_ID"
  type  = "String"
  value = aws_cognito_user_pool_client.discourse_dev.id
  tags  = local.tags
}

resource "aws_ssm_parameter" "cognito_client_secret" {
  name  = "${local.ssm_prefix}/COGNITO_CLIENT_SECRET"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.discourse_dev.client_secret
  tags  = local.tags
}

resource "aws_ssm_parameter" "cognito_issuer" {
  name  = "${local.ssm_prefix}/COGNITO_ISSUER"
  type  = "String"
  value = "https://cognito-idp.${var.region}.amazonaws.com/${local.cognito_user_pool_id}"
  tags  = local.tags
}

resource "aws_ssm_parameter" "cognito_domain" {
  name  = "${local.ssm_prefix}/COGNITO_DOMAIN"
  type  = "String"
  value = local.cognito_domain
  tags  = local.tags
}

resource "aws_ssm_parameter" "discourse_connect_secret" {
  name  = "${local.ssm_prefix}/DISCOURSE_CONNECT_SECRET"
  type  = "SecureString"
  value = var.discourse_connect_secret
  tags  = local.tags
}

###############################################
# Discourse Modules
###############################################

# Redis (small instance for dev)
module "discourse_redis" {
  source = "../../modules/discourse-redis"

  project_id             = local.project_id
  environment            = local.environment
  vpc_id                 = local.vpc_id
  private_subnet_ids     = local.private_subnet_ids
  ecs_security_group_id  = local.ecs_security_group_id
  node_type              = "cache.t4g.micro"  # Smallest for dev
  num_replicas           = 1                   # No HA in dev
  ssm_prefix             = local.ssm_prefix
  
  tags = local.tags
}

# Storage
module "discourse_storage" {
  source = "../../modules/discourse-storage"

  project_id             = local.project_id
  region                 = var.region
  ecs_task_role_arn      = aws_iam_role.ecs_task.arn
  allowed_origins        = [local.discourse_hostname]
  enable_versioning      = false               # No versioning in dev
  create_backup_bucket   = false               # No backup bucket in dev
  ssm_prefix             = local.ssm_prefix
  
  tags = local.tags
}

# ALB Integration
module "discourse_alb" {
  source = "../../modules/discourse-alb"

  project_id             = local.project_id
  vpc_id                 = local.vpc_id
  alb_arn                = local.alb_arn
  alb_dns_name           = local.alb_dns_name
  alb_zone_id            = local.alb_zone_id
  route53_zone_id        = data.aws_route53_zone.primary.zone_id
  discourse_hostnames    = [local.discourse_hostname]
  listener_rule_priority = 200 + var.listener_priority_offset
  enable_blue_green      = false               # No blue/green in dev
  
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
  
  task_cpu                 = 512               # Smaller for dev
  task_memory              = 1024              # Smaller for dev
  desired_count            = 1
  
  ecr_repository_url       = var.ecr_repository_url
  image_tag                = var.discourse_image_tag
  
  primary_hostname         = local.discourse_hostname
  cdn_url                  = ""
  ssm_prefix               = local.ssm_prefix
  discourse_connect_provider_url = "https://app.${var.domain}/sso/discourse"
  
  target_group_arn         = module.discourse_alb.target_group_arn
  target_group_name        = module.discourse_alb.target_group_name
  alb_name                 = split("/", local.alb_arn)[1]
  
  enable_blue_green        = false
  
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 2                 # Low max for dev
  cpu_target_value         = 70
  memory_target_value      = 80
  
  log_retention_days       = 3                 # Short retention for dev
  alarm_actions            = []
  
  tags = local.tags
  
  depends_on = [
    aws_rds_cluster_instance.dev_aurora_instance,
    module.discourse_redis,
    module.discourse_storage,
    module.discourse_alb
  ]
}
