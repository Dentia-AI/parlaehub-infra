#!/bin/bash
set -e

###############################################
# Destroy Dev Environment
# 
# Complete teardown of dev infrastructure
# including database, Redis, S3, ECS, etc.
###############################################

ENVIRONMENT=${1:-dev}
PROFILE=${2:-dentia}
REGION=${3:-us-east-2}

if [ "$ENVIRONMENT" = "production" ]; then
  echo "=========================================="
  echo "ERROR: Cannot destroy production!"
  echo "=========================================="
  echo ""
  echo "This script is only for dev/staging environments."
  echo "For production, manually run terraform destroy after approval."
  exit 1
fi

echo "=========================================="
echo "⚠️  ParlaeHub Environment Destruction"
echo "Environment: $ENVIRONMENT"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will permanently delete:"
echo "  - ECS Service and Tasks"
echo "  - Redis Cluster"
echo "  - S3 Buckets (and all contents)"
echo "  - Database: parlaehub_${ENVIRONMENT}"
echo "  - ECR Images"
echo "  - CloudWatch Logs"
echo "  - All SSM Parameters"
echo "  - Target Groups and ALB Rules"
echo ""
read -p "Are you absolutely sure? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Starting destruction process..."
echo ""

# Step 1: Destroy database
echo "=========================================="
echo "Step 1: Destroying Database"
echo "=========================================="
cd ../../parlaehub
if [ -f "scripts/destroy-database.sh" ]; then
  echo "yes" | ./scripts/destroy-database.sh "$ENVIRONMENT" "$PROFILE" "$REGION"
else
  echo "⚠️  Warning: Database destroy script not found, skipping..."
fi

# Step 2: Destroy Terraform infrastructure
echo ""
echo "=========================================="
echo "Step 2: Destroying Terraform Infrastructure"
echo "=========================================="
cd ../parlaehub-infra/environments/$ENVIRONMENT

# Empty S3 buckets first (they can't be destroyed if not empty)
echo "Emptying S3 buckets..."
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
if [ -n "$S3_BUCKET" ]; then
  echo "Emptying bucket: $S3_BUCKET"
  aws s3 rm "s3://$S3_BUCKET" --recursive --profile "$PROFILE" --region "$REGION" 2>/dev/null || true
fi

# Destroy infrastructure
echo ""
echo "Running terraform destroy..."
terraform destroy -auto-approve

echo ""
echo "=========================================="
echo "✓ Environment destruction complete!"
echo "=========================================="
echo ""
echo "Destroyed environment: $ENVIRONMENT"
echo ""
echo "To recreate, run:"
echo "  cd parlaehub-infra/environments/$ENVIRONMENT"
echo "  terraform init"
echo "  terraform apply"
echo ""

