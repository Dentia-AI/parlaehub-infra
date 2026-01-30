#!/usr/bin/env bash
set -euo pipefail

# deploy-dev.sh
# Creates/updates a ParlaeHub dev environment

BRANCH_NAME="${1:-}"
AWS_PROFILE="${2:-dentia}"
REGION="${3:-us-east-2}"

if [ -z "$BRANCH_NAME" ]; then
  echo "Usage: ./deploy-dev.sh <branch-name> [aws-profile] [region]"
  echo ""
  echo "Example:"
  echo "  ./deploy-dev.sh feature-123 dentia us-east-2"
  echo ""
  echo "This will create/update a dev environment for 'feature-123'"
  echo "  URL: https://dev-feature-123.hub.dentiaapp.com"
  exit 1
fi

# Safety check
if [ "$BRANCH_NAME" = "production" ] || [ "$BRANCH_NAME" = "prod" ]; then
  echo "❌ ERROR: Use production deployment for production!"
  exit 1
fi

# Sanitize branch name for resource naming
SAFE_BRANCH=$(echo "$BRANCH_NAME" | tr '/' '-' | tr '_' '-' | tr '[:upper:]' '[:lower:]')

echo "═══════════════════════════════════════════════════════════════"
echo "  ParlaeHub Dev Environment Deployment"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Branch: $BRANCH_NAME"
echo "Safe Name: $SAFE_BRANCH"
echo "AWS Profile: $AWS_PROFILE"
echo "Region: $REGION"
echo ""
echo "Environment URL: https://dev-${SAFE_BRANCH}.hub.dentiaapp.com"
echo ""

# Check if Terraform state bucket exists
echo "1️⃣  Checking Terraform state bucket..."
if ! aws s3api head-bucket --bucket "parlaehub-terraform-state" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null; then
  echo "   Creating Terraform state bucket..."
  aws s3api create-bucket \
    --bucket "parlaehub-terraform-state" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    --profile "$AWS_PROFILE"
  
  aws s3api put-bucket-versioning \
    --bucket "parlaehub-terraform-state" \
    --versioning-configuration Status=Enabled \
    --profile "$AWS_PROFILE" \
    --region "$REGION"
  
  aws s3api put-bucket-encryption \
    --bucket "parlaehub-terraform-state" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }' \
    --profile "$AWS_PROFILE" \
    --region "$REGION"
fi

# Check if DynamoDB lock table exists
echo ""
echo "2️⃣  Checking DynamoDB lock table..."
if ! aws dynamodb describe-table --table-name "parlaehub-terraform-locks" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null; then
  echo "   Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --table-name "parlaehub-terraform-locks" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --profile "$AWS_PROFILE" \
    --region "$REGION"
  
  echo "   Waiting for table to be active..."
  aws dynamodb wait table-exists \
    --table-name "parlaehub-terraform-locks" \
    --profile "$AWS_PROFILE" \
    --region "$REGION"
fi

# Generate random password for Aurora
echo ""
echo "3️⃣  Generating Aurora password..."
AURORA_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

# Initialize Terraform
echo ""
echo "4️⃣  Initializing Terraform..."
terraform init \
  -backend-config="profile=$AWS_PROFILE" \
  -backend-config="region=$REGION" \
  -reconfigure

# Create/select workspace
echo ""
echo "5️⃣  Creating/selecting Terraform workspace: $BRANCH_NAME..."
terraform workspace select "$BRANCH_NAME" 2>/dev/null || terraform workspace new "$BRANCH_NAME"

# Plan
echo ""
echo "6️⃣  Planning infrastructure..."
terraform plan \
  -var="branch_name=$BRANCH_NAME" \
  -var="profile=$AWS_PROFILE" \
  -var="region=$REGION" \
  -var="aurora_dev_password=$AURORA_PASSWORD" \
  -out=tfplan

# Apply
echo ""
echo "7️⃣  Applying infrastructure..."
read -p "Continue with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Deployment cancelled."
  rm -f tfplan
  exit 1
fi

terraform apply tfplan
rm -f tfplan

# Get outputs
echo ""
echo "8️⃣  Retrieving environment details..."
DISCOURSE_URL=$(terraform output -raw discourse_url 2>/dev/null || echo "https://dev-${SAFE_BRANCH}.hub.dentiaapp.com")
DB_HOST=$(terraform output -raw db_endpoint 2>/dev/null || echo "N/A")
REDIS_HOST=$(terraform output -raw redis_endpoint 2>/dev/null || echo "N/A")

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Dev Environment Deployed"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Branch: $BRANCH_NAME"
echo "Environment: dev-${SAFE_BRANCH}"
echo ""
echo "📝 Access Details:"
echo "  URL: $DISCOURSE_URL"
echo "  Database: $DB_HOST"
echo "  Redis: $REDIS_HOST"
echo ""
echo "🔒 Credentials stored in SSM:"
echo "  Prefix: /parlaehub/dev/${SAFE_BRANCH}"
echo ""
echo "📋 Next Steps:"
echo "  1. Build and push Docker image:"
echo "     cd ../../parlaehub"
echo "     ./scripts/build-and-push.sh dev ${SAFE_BRANCH} $AWS_PROFILE $REGION"
echo ""
echo "  2. Deploy to ECS:"
echo "     aws ecs update-service \\"
echo "       --cluster dentia-cluster \\"
echo "       --service parlaehub-dev-${SAFE_BRANCH}-discourse \\"
echo "       --force-new-deployment \\"
echo "       --profile $AWS_PROFILE --region $REGION"
echo ""
echo "  3. Monitor deployment:"
echo "     aws ecs describe-services \\"
echo "       --cluster dentia-cluster \\"
echo "       --services parlaehub-dev-${SAFE_BRANCH}-discourse \\"
echo "       --profile $AWS_PROFILE --region $REGION \\"
echo "       | jq '.services[0].events[:5]'"
echo ""
echo "🗑️  To destroy this environment:"
echo "     ./destroy-dev.sh $BRANCH_NAME $AWS_PROFILE $REGION"
echo ""
echo "═══════════════════════════════════════════════════════════════"

