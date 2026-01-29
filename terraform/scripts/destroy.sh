#!/bin/bash
# Destruction script for Private AKS Cluster
# Usage: ./scripts/destroy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Azure CLI is installed and authenticated
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi

    # Check Azure authentication
    if ! az account show &> /dev/null; then
        log_error "Not authenticated with Azure CLI. Run 'az login'"
        exit 1
    fi

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."
    cd "$PROJECT_ROOT"

    terraform init

    log_info "Terraform initialized"
}

# Plan destruction
plan_destruction() {
    log_info "Planning destruction..."
    cd "$PROJECT_ROOT"

    if [[ ! -f "terraform.tfvars" ]]; then
        log_error "terraform.tfvars file not found"
        log_info "Please ensure the terraform.tfvars file exists"
        exit 1
    fi

    terraform plan -destroy -out="destroy.tfplan"
    log_info "Destruction plan completed. Review the output above."
}

# Apply destruction
apply_destruction() {
    log_info "Applying destruction..."
    cd "$PROJECT_ROOT"

    if [[ ! -f "destroy.tfplan" ]]; then
        log_error "Destruction plan file not found: destroy.tfplan"
        log_info "Run the plan step first"
        exit 1
    fi

    terraform apply "destroy.tfplan"
    rm -f "destroy.tfplan"

    log_info "Destruction completed successfully!"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    cd "$PROJECT_ROOT"
    rm -f destroy*.tfplan
}

# Main destruction function
main() {
    log_info "Starting AKS cluster destruction process..."

    check_prerequisites
    init_terraform
    plan_destruction

    # Multiple confirmations for safety
    log_warn "WARNING: You are about to DESTROY the AKS cluster and ALL associated resources"
    log_warn "This action is IRREVERSIBLE and will DELETE ALL INFRASTRUCTURE"
    echo ""
    read -p "Type 'DESTROY CLUSTER' to confirm: " -r
    if [[ ! $REPLY == "DESTROY CLUSTER" ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi
    echo ""
    read -p "Are you absolutely sure? Type 'yes' to proceed: " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi

    apply_destruction
    cleanup
    log_info "Destruction process completed!"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"