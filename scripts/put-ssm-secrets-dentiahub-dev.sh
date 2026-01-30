#!/usr/bin/env bash
set -euo pipefail

##############################################
# ParlaeHub Dev Secrets Setup
# Stores secrets in AWS SSM Parameter Store
##############################################

PROFILE=${1:-dentia}
REGION=${2:-us-east-2}
ENV_SUFFIX=${3:-dev}

if ! command -v aws >/dev/null; then
  echo "ERROR: aws CLI is required on PATH." >&2
  exit 1
fi

echo "=========================================="
echo "  ParlaeHub Dev Secrets Setup"
echo "=========================================="
echo "AWS Profile: $PROFILE"
echo "Region: $REGION"
echo "Environment: $ENV_SUFFIX"
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

# ==========================================
# Dev Configuration (Simpler than Production)
# ==========================================

echo "📊 Dev Configuration"
echo "----------------------------------------"

# Dev database (will be created by Terraform)
DB_PASSWORD="dev_password_$(openssl rand -hex 8)"
echo -e "${GREEN}✓${NC} Generated dev database password"

# Get Cognito User Pool ID from Dentia infrastructure
COGNITO_USER_POOL_ID=$(aws cognito-idp list-user-pools \
  --region "$REGION" \
  --profile "$PROFILE" \
  --max-results 10 \
  --query "UserPools[?starts_with(Name, 'dentia')].Id" \
  --output text | head -n1)

if [ -z "$COGNITO_USER_POOL_ID" ]; then
  echo -e "${RED}✗${NC} Could not find Cognito User Pool"
  echo "Please run production setup first or manually specify"
  exit 1
fi

echo -e "${GREEN}✓${NC} Found Cognito User Pool: $COGNITO_USER_POOL_ID"

COGNITO_ISSUER="https://cognito-idp.${REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}"

# Generate Discourse secret (simpler for dev)
DISCOURSE_SECRET_KEY_BASE=$(openssl rand -hex 32)
echo -e "${GREEN}✓${NC} Generated Discourse secret"

# ==========================================
# Write Parameters to SSM
# ==========================================

echo ""
echo "📝 Writing parameters to SSM..."
echo "=========================================="

SSM_PREFIX="/parlaehub/dev/${ENV_SUFFIX}"

# Database (Aurora endpoint will be set by Terraform)
put_param "${SSM_PREFIX}/DB_PASSWORD" "$DB_PASSWORD" "SecureString"

# Discourse secrets
put_param "${SSM_PREFIX}/DISCOURSE_SECRET_KEY_BASE" "$DISCOURSE_SECRET_KEY_BASE" "SecureString"

# Cognito
put_param "${SSM_PREFIX}/COGNITO_USER_POOL_ID" "$COGNITO_USER_POOL_ID"
put_param "${SSM_PREFIX}/COGNITO_ISSUER" "$COGNITO_ISSUER"

# AWS Region
put_param "${SSM_PREFIX}/AWS_REGION" "$REGION"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Dev parameters uploaded successfully!${NC}"
echo "=========================================="
echo ""
echo "Environment: $ENV_SUFFIX"
echo "SSM Prefix: $SSM_PREFIX"
echo ""
echo "Note: Database and Redis endpoints will be set by Terraform"
echo ""

