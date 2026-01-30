###############################################
# Discourse Storage Module
# S3 bucket for uploads, avatars, backups
###############################################

# S3 bucket for uploads
resource "aws_s3_bucket" "uploads" {
  bucket = "${var.project_id}-uploads"
  
  tags = merge(var.tags, {
    Name = "${var.project_id}-uploads"
    Purpose = "Discourse uploads and attachments"
  })

  lifecycle {
    prevent_destroy = false  # Set via var.protect_resources
  }
}

# Bucket versioning
resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Ownership controls (disable ACLs, use bucket owner enforced)
resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    object_ownership = "BucketOwnerEnforced"  # Disables ACLs
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for old versions
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CORS configuration for direct uploads
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = var.allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Bucket policy for ECS task access
resource "aws_s3_bucket_policy" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  policy = data.aws_iam_policy_document.uploads_policy.json
}

data "aws_iam_policy_document" "uploads_policy" {
  # Allow ECS tasks to read/write
  statement {
    sid    = "AllowECSTaskAccess"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [var.ecs_task_role_arn]
    }
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.uploads.arn,
      "${aws_s3_bucket.uploads.arn}/*"
    ]
  }

  # Allow CloudFront access (if using CDN)
  dynamic "statement" {
    for_each = var.cloudfront_oai_arn != "" ? [1] : []
    
    content {
      sid    = "AllowCloudFrontAccess"
      effect = "Allow"
      
      principals {
        type        = "AWS"
        identifiers = [var.cloudfront_oai_arn]
      }
      
      actions = [
        "s3:GetObject"
      ]
      
      resources = [
        "${aws_s3_bucket.uploads.arn}/*"
      ]
    }
  }
}

# Optional: S3 bucket for backups
resource "aws_s3_bucket" "backups" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = "${var.project_id}-backups"
  
  tags = merge(var.tags, {
    Name = "${var.project_id}-backups"
    Purpose = "Discourse database backups"
  })

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backups[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  count  = var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backups[0].id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

# Store S3 info in SSM
resource "aws_ssm_parameter" "s3_bucket" {
  name        = "${var.ssm_prefix}/S3_BUCKET"
  description = "S3 bucket for Discourse uploads"
  type        = "String"
  value       = aws_s3_bucket.uploads.id
  
  tags = var.tags
}

resource "aws_ssm_parameter" "s3_region" {
  name        = "${var.ssm_prefix}/S3_REGION"
  description = "S3 bucket region"
  type        = "String"
  value       = var.region
  
  tags = var.tags
}

resource "aws_ssm_parameter" "s3_backup_bucket" {
  count       = var.create_backup_bucket ? 1 : 0
  name        = "${var.ssm_prefix}/S3_BACKUP_BUCKET"
  description = "S3 bucket for Discourse backups"
  type        = "String"
  value       = aws_s3_bucket.backups[0].id
  
  tags = var.tags
}

