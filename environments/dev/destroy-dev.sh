#!/usr/bin/env bash
set -euo pipefail

# destroy-dev.sh
# Safely destroys a ParlaeHub dev environment

BRANCH_NAME="${1:-}"
AWS_PROFILE="${2:-dentia}"
REGION="${3:-us-east-2}"

if [ -z "$BRANCH_NAME" ]; then
  echo "Usage: ./destroy-dev.sh <branch-name> [aws-profile] [region]"
  echo ""
  echo "Example:"
  echo "  ./destroy-dev.sh feature-123 dentia us-east-2"
  echo ""
  echo "This will destroy the dev environment for 'feature-123'"
  exit 1
fi

# Safety check: Prevent destroying production
if [ "$BRANCH_NAME" = "production" ] || [ "$BRANCH_NAME" = "prod" ] || [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
  echo "❌ ERROR: Cannot destroy production/main branch environments with this script!"
  echo ""
  echo "Branch name: $BRANCH_NAME"
  echo ""
  echo "If you really need to destroy production, use the production destroy script."
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "  ⚠️  DESTROYING ParlaeHub Dev Environment"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Branch: $BRANCH_NAME"
echo "AWS Profile: $AWS_PROFILE"
echo "Region: $REGION"
echo ""
echo "This will destroy:"
echo "  • ECS Service"
echo "  • Aurora Serverless v2 cluster"
echo "  • ElastiCache Redis"
echo "  • S3 buckets and contents"
echo "  • ALB target groups"
echo "  • Route53 DNS records"
echo "  • SSM parameters"
echo "  • Cognito app client"
echo ""
read -p "Are you sure? Type 'destroy-${BRANCH_NAME}' to confirm: " CONFIRM

if [ "$CONFIRM" != "destroy-${BRANCH_NAME}" ]; then
  echo "❌ Destruction cancelled."
  exit 1
fi

echo ""
echo "Proceeding with destruction..."
echo ""

# Initialize Terraform
echo "1️⃣  Initializing Terraform..."
terraform init \
  -backend-config="profile=$AWS_PROFILE" \
  -backend-config="region=$REGION" \
  -reconfigure

# Select workspace (or create if doesn't exist)
echo ""
echo "2️⃣  Selecting Terraform workspace: $BRANCH_NAME..."
terraform workspace select "$BRANCH_NAME" 2>/dev/null || terraform workspace new "$BRANCH_NAME"

# Destroy infrastructure
echo ""
echo "3️⃣  Destroying infrastructure..."
terraform destroy \
  -var="branch_name=$BRANCH_NAME" \
  -var="profile=$AWS_PROFILE" \
  -var="region=$REGION" \
  -var="aurora_dev_password=dummy" \
  -auto-approve

# Delete workspace
echo ""
echo "4️⃣  Deleting Terraform workspace..."
terraform workspace select default
terraform workspace delete "$BRANCH_NAME" -force

# Clean up any remaining S3 objects (in case bucket deletion failed)
echo ""
echo "5️⃣  Cleaning up S3 buckets..."
BUCKET_PREFIX="parlaehub-dev-$(echo $BRANCH_NAME | tr '/' '-')"
aws s3api list-buckets \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --query "Buckets[?starts_with(Name, '$BUCKET_PREFIX')].Name" \
  --output text | while read BUCKET; do
    if [ -n "$BUCKET" ]; then
      echo "   Removing objects from $BUCKET..."
      aws s3 rm "s3://$BUCKET" --recursive --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null || true
      echo "   Deleting bucket $BUCKET..."
      aws s3api delete-bucket --bucket "$BUCKET" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null || true
    fi
  done

# Clean up SSM parameters
echo ""
echo "6️⃣  Cleaning up SSM parameters..."
SSM_PREFIX="/parlaehub/dev/$(echo $BRANCH_NAME | tr '/' '-')"
aws ssm describe-parameters \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --parameter-filters "Key=Name,Option=BeginsWith,Values=$SSM_PREFIX" \
  --query "Parameters[].Name" \
  --output text | while read PARAM; do
    if [ -n "$PARAM" ]; then
      echo "   Deleting $PARAM..."
      aws ssm delete-parameter --name "$PARAM" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null || true
    fi
  done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Dev Environment Destroyed"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Branch: $BRANCH_NAME"
echo ""
echo "Destroyed resources:"
echo "  ✓ ECS Service"
echo "  ✓ Aurora cluster"
echo "  ✓ Redis"
echo "  ✓ S3 buckets"
echo "  ✓ Target groups"
echo "  ✓ DNS records"
echo "  ✓ SSM parameters"
echo "  ✓ Cognito client"
echo ""
echo "The dev environment has been completely removed."
echo ""
echo "═══════════════════════════════════════════════════════════════"

