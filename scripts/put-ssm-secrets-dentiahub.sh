#!/usr/bin/env bash
set -euo pipefail

##############################################
# ParlaeHub Production Secrets Setup
# Stores secrets in AWS SSM Parameter Store
##############################################

PROFILE=${1:-dentia}
REGION=${2:-us-east-2}

if ! command -v aws >/dev/null; then
  echo "ERROR: aws CLI is required on PATH." >&2
  exit 1
fi

echo "=========================================="
echo "  ParlaeHub Production Secrets Setup"
echo "=========================================="
echo "AWS Profile: $PROFILE"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

put_param() {
  local name="$1"
  local value="$2"
  local type="${3:-String}"
  
  if aws ssm put-parameter \
    --name "$name" \
    --value "$value" \
    --type "$type" \
    --overwrite \
    --region "$REGION" \
    --profile "$PROFILE" \
    >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Set $name"
  else
    echo -e "${RED}✗${NC} Failed to set $name" >&2
    return 1
  fi
}

prompt_secret() {
  local var_name="$1"
  local prompt_text="$2"
  local current_val="${!var_name:-}"
  
  if [ -z "$current_val" ]; then
    echo -e "${YELLOW}${prompt_text}:${NC}"
    read -r -p "> " value
    eval "$var_name='$value'"
  fi
}

# ==========================================
# Get Database Connection Details
# ==========================================

echo "📊 Database Configuration"
echo "----------------------------------------"

# Get Aurora cluster endpoint from Dentia infrastructure
AURORA_ENDPOINT=$(aws rds describe-db-clusters \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "DBClusters[?starts_with(DBClusterIdentifier, 'dentia')].Endpoint" \
  --output text | head -n1)

if [ -z "$AURORA_ENDPOINT" ]; then
  prompt_secret AURORA_ENDPOINT "Enter Aurora cluster endpoint"
else
  echo -e "${GREEN}✓${NC} Found Aurora endpoint: $AURORA_ENDPOINT"
fi

DB_HOST="$AURORA_ENDPOINT"
DB_NAME="discourse_production"
DB_PORT="5432"
DB_USERNAME="discourse_user"

prompt_secret DB_PASSWORD "Enter Discourse database password (generate strong password)"

# ==========================================
# Get Redis Connection Details
# ==========================================

echo ""
echo "🔴 Redis Configuration"
echo "----------------------------------------"
echo -e "${YELLOW}Note: Redis endpoint will be created by Terraform${NC}"
echo "Skipping Redis configuration..."

# ==========================================
# Get Cognito Details
# ==========================================

echo ""
echo "🔐 Cognito Configuration"
echo "----------------------------------------"

# Get Cognito User Pool ID from Dentia infrastructure
COGNITO_USER_POOL_ID=$(aws cognito-idp list-user-pools \
  --region "$REGION" \
  --profile "$PROFILE" \
  --max-results 10 \
  --query "UserPools[?starts_with(Name, 'dentia')].Id" \
  --output text | head -n1)

if [ -z "$COGNITO_USER_POOL_ID" ]; then
  prompt_secret COGNITO_USER_POOL_ID "Enter Cognito User Pool ID"
else
  echo -e "${GREEN}✓${NC} Found Cognito User Pool: $COGNITO_USER_POOL_ID"
fi

COGNITO_ISSUER="https://cognito-idp.${REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}"

echo -e "${YELLOW}Note: Cognito client ID and secret will be created by Terraform${NC}"

# ==========================================
# Get S3 Bucket Details
# ==========================================

echo ""
echo "📦 S3 Configuration"
echo "----------------------------------------"
echo -e "${YELLOW}Note: S3 buckets will be created by Terraform${NC}"

# ==========================================
# Additional Discourse Secrets
# ==========================================

echo ""
echo "🔑 Discourse Secrets"
echo "----------------------------------------"

# Generate secure random secrets if not provided
if ! command -v openssl >/dev/null; then
  echo -e "${YELLOW}⚠${NC}  openssl not found, please enter secrets manually"
  prompt_secret DISCOURSE_SECRET_KEY_BASE "Enter Discourse secret_key_base (64+ chars)"
else
  DISCOURSE_SECRET_KEY_BASE=$(openssl rand -hex 64)
  echo -e "${GREEN}✓${NC} Generated secret_key_base"
fi

prompt_secret DISCOURSE_CONNECT_SECRET "Enter DiscourseConnect shared secret (must match frontend DISCOURSE_SSO_SECRET)"

# ==========================================
# Write Parameters to SSM
# ==========================================

echo ""
echo "📝 Writing parameters to SSM..."
echo "=========================================="

SSM_PREFIX="/parlaehub/production"

# Database parameters
put_param "${SSM_PREFIX}/DB_HOST" "$DB_HOST"
put_param "${SSM_PREFIX}/DB_NAME" "$DB_NAME"
put_param "${SSM_PREFIX}/DB_USERNAME" "$DB_USERNAME"
put_param "${SSM_PREFIX}/DB_PASSWORD" "$DB_PASSWORD" "SecureString"

# Discourse secrets
put_param "${SSM_PREFIX}/DISCOURSE_SECRET_KEY_BASE" "$DISCOURSE_SECRET_KEY_BASE" "SecureString"
put_param "${SSM_PREFIX}/DISCOURSE_CONNECT_SECRET" "$DISCOURSE_CONNECT_SECRET" "SecureString"

# Cognito (partial - rest created by Terraform)
put_param "${SSM_PREFIX}/COGNITO_USER_POOL_ID" "$COGNITO_USER_POOL_ID"
put_param "${SSM_PREFIX}/COGNITO_ISSUER" "$COGNITO_ISSUER"

# AWS Region
put_param "${SSM_PREFIX}/AWS_REGION" "$REGION"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ All parameters uploaded successfully!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Run Terraform to create remaining resources"
echo "2. Deploy Discourse container"
echo "3. Run database migrations"
echo ""
echo "To view parameters:"
echo "  aws ssm get-parameters-by-path --path \"${SSM_PREFIX}\" --recursive --profile $PROFILE --region $REGION"
echo ""
