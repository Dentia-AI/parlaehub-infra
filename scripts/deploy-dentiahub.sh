#!/usr/bin/env bash
#
# Deploy parlaehub (Discourse forum)
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

cd "${ROOT_DIR}/parlaehub"

# Use the build-and-deploy script
log_info "Building and deploying Discourse..."
./scripts/build-and-deploy-discourse.sh "${ENVIRONMENT}"

log_success "Forum deployed!"

