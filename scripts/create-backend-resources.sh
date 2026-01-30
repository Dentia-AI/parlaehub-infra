#!/usr/bin/env bash
set -euo pipefail

##############################################
# Create Terraform Backend Resources
# S3 bucket and DynamoDB table for state
##############################################

PROFILE=${1:-dentia}
REGION=${2:-us-east-2}

BUCKET_NAME="parlaehub-terraform-state"
DYNAMODB_TABLE="parlaehub-terraform-locks"

echo "=========================================="
echo "  ParlaeHub Terraform Backend Setup"
echo "=========================================="
echo "AWS Profile: $PROFILE"
echo "Region: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "DynamoDB: $DYNAMODB_TABLE"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if bucket exists
if aws s3 ls "s3://${BUCKET_NAME}" --region "$REGION" --profile "$PROFILE" >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠${NC}  S3 bucket already exists: $BUCKET_NAME"
else
  echo "Creating S3 bucket..."
  aws s3 mb "s3://${BUCKET_NAME}" \
    --region "$REGION" \
    --profile "$PROFILE"
  
  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled \
    --region "$REGION" \
    --profile "$PROFILE"
  
  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }' \
    --region "$REGION" \
    --profile "$PROFILE"
  
  # Block public access
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --region "$REGION" \
    --profile "$PROFILE"
  
  echo -e "${GREEN}✓${NC} Created S3 bucket: $BUCKET_NAME"
fi

# Check if DynamoDB table exists
if aws dynamodb describe-table \
  --table-name "$DYNAMODB_TABLE" \
  --region "$REGION" \
  --profile "$PROFILE" >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠${NC}  DynamoDB table already exists: $DYNAMODB_TABLE"
else
  echo "Creating DynamoDB table..."
  aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --profile "$PROFILE" \
    >/dev/null
  
  echo "Waiting for table to be created..."
  aws dynamodb wait table-exists \
    --table-name "$DYNAMODB_TABLE" \
    --region "$REGION" \
    --profile "$PROFILE"
  
  echo -e "${GREEN}✓${NC} Created DynamoDB table: $DYNAMODB_TABLE"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Terraform backend resources ready!${NC}"
echo "=========================================="
echo ""
echo "Backend configuration:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    key            = \"<environment>/terraform.tfstate\""
echo "    region         = \"${REGION}\""
echo "    profile        = \"${PROFILE}\""
echo "    encrypt        = true"
echo "    dynamodb_table = \"${DYNAMODB_TABLE}\""
echo "  }"
echo "}"
echo ""

