###############################################
# Discourse Database Module
# Creates a separate database in shared Aurora cluster
###############################################

# Create database in shared Aurora cluster
resource "null_resource" "create_database" {
  count = var.create_database ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      PGPASSWORD='${var.aurora_master_password}' psql \
        -h ${var.aurora_endpoint} \
        -U ${var.aurora_master_username} \
        -d postgres \
        -c "SELECT 1 FROM pg_database WHERE datname = '${var.database_name}'" | grep -q 1 || \
      PGPASSWORD='${var.aurora_master_password}' psql \
        -h ${var.aurora_endpoint} \
        -U ${var.aurora_master_username} \
        -d postgres \
        -c "CREATE DATABASE ${var.database_name};"
    EOT
  }

  triggers = {
    database_name = var.database_name
    cluster_id    = var.aurora_cluster_id
  }
}

# Create dedicated DB user for Discourse
resource "null_resource" "create_db_user" {
  count = var.create_database && var.create_user ? 1 : 0

  depends_on = [null_resource.create_database]

  provisioner "local-exec" {
    command = <<-EOT
      PGPASSWORD='${var.aurora_master_password}' psql \
        -h ${var.aurora_endpoint} \
        -U ${var.aurora_master_username} \
        -d ${var.database_name} \
        -c "DO \$\$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${var.db_username}') THEN
            CREATE USER ${var.db_username} WITH PASSWORD '${var.db_password}';
          END IF;
        END
        \$\$;
        GRANT ALL PRIVILEGES ON DATABASE ${var.database_name} TO ${var.db_username};
        GRANT ALL ON SCHEMA public TO ${var.db_username};"
    EOT
  }

  triggers = {
    db_username   = var.db_username
    database_name = var.database_name
  }
}

# Construct DATABASE_URL for Discourse
locals {
  db_password_encoded = urlencode(var.db_password)
  database_url = "postgresql://${var.db_username}:${local.db_password_encoded}@${var.aurora_endpoint}:5432/${var.database_name}?sslmode=require"
}

# Store DATABASE_URL in SSM Parameter Store
resource "aws_ssm_parameter" "database_url" {
  name        = "${var.ssm_prefix}/DATABASE_URL"
  description = "Discourse database connection string"
  type        = "SecureString"
  value       = local.database_url
  overwrite   = true
  
  tags = var.tags
}

# Store individual DB connection parameters
resource "aws_ssm_parameter" "db_host" {
  name        = "${var.ssm_prefix}/DB_HOST"
  description = "Database host"
  type        = "String"
  value       = var.aurora_endpoint
  overwrite   = true
  
  tags = var.tags
}

resource "aws_ssm_parameter" "db_name" {
  name        = "${var.ssm_prefix}/DB_NAME"
  description = "Database name"
  type        = "String"
  value       = var.database_name
  overwrite   = true
  
  tags = var.tags
}

resource "aws_ssm_parameter" "db_username" {
  name        = "${var.ssm_prefix}/DB_USERNAME"
  description = "Database username"
  type        = "String"
  value       = var.db_username
  overwrite   = true
  
  tags = var.tags
}

resource "aws_ssm_parameter" "db_password" {
  name        = "${var.ssm_prefix}/DB_PASSWORD"
  description = "Database password"
  type        = "SecureString"
  value       = var.db_password
  overwrite   = true
  
  tags = var.tags
}

