#!/usr/bin/env bash
#
# Deploy parlaehub infrastructure
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/config.sh"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }

ENV_DIR="${ROOT_DIR}/parlaehub-infra/environments/${ENVIRONMENT}"

if [[ ! -d "${ENV_DIR}" ]]; then
  log_error "Environment directory not found: ${ENV_DIR}"
  exit 1
fi

cd "${ENV_DIR}"

# Create terraform.tfvars from config
cat > terraform.tfvars <<EOF
region  = "${AWS_REGION}"
profile = "${AWS_PROFILE}"
domain  = "${APEX_DOMAIN}"

aurora_master_username = "${DB_MASTER_USERNAME:-admin}"
aurora_master_password = "${DB_MASTER_PASSWORD}"

discourse_db_password = "${DISCOURSE_DB_PASSWORD}"

# From main infrastructure
vpc_id     = ""  # Will be imported from data source
subnet_ids = []  # Will be imported from data source
EOF

log_info "Initializing Terraform..."
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${PROJECT_NAME}/parlaehub-infra/${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${TF_STATE_REGION}" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
  -backend-config="profile=${AWS_PROFILE}"

log_info "Planning infrastructure changes..."
terraform plan -out=tfplan

log_info "Applying infrastructure changes..."
terraform apply tfplan

log_success "Forum infrastructure deployed!"

# Save outputs
mkdir -p "${ROOT_DIR}/.outputs"
terraform output -json > "${ROOT_DIR}/.outputs/parlaehub-infra.json"

