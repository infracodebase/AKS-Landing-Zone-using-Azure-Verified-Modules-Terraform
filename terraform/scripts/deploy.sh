#!/bin/bash
# Deployment script for Private AKS Cluster
# Usage: ./scripts/deploy.sh

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

    # Check Terraform version
    terraform_version=$(terraform version -json | jq -r '.terraform_version')
    if [[ "$terraform_version" < "1.9.0" ]]; then
        log_error "Terraform version must be >= 1.9.0. Current version: $terraform_version"
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

# Plan deployment
plan_deployment() {
    log_info "Planning deployment..."
    cd "$PROJECT_ROOT"

    if [[ ! -f "terraform.tfvars" ]]; then
        log_error "terraform.tfvars file not found"
        log_info "Please create the file based on terraform.tfvars.example"
        exit 1
    fi

    terraform plan -out="deployment.tfplan"
    log_info "Plan completed. Review the output above."
}

# Apply deployment
apply_deployment() {
    log_info "Applying deployment..."
    cd "$PROJECT_ROOT"

    if [[ ! -f "deployment.tfplan" ]]; then
        log_error "Plan file not found: deployment.tfplan"
        log_info "Run the plan step first"
        exit 1
    fi

    terraform apply "deployment.tfplan"
    rm -f "deployment.tfplan"

    log_info "Deployment completed successfully!"
}

# Get cluster credentials
get_credentials() {
    log_info "Retrieving cluster credentials..."
    cd "$PROJECT_ROOT"

    local resource_group=$(terraform output -raw resource_group_name)
    local cluster_name=$(terraform output -raw cluster_name)

    az aks get-credentials --resource-group "$resource_group" --name "$cluster_name" --overwrite-existing

    log_info "Credentials configured. Testing connection..."
    kubectl get nodes

    log_info "Cluster access configured successfully!"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    cd "$PROJECT_ROOT"
    rm -f *.tfplan
}

# Main deployment function
main() {
    log_info "Starting AKS private cluster deployment..."

    check_prerequisites
    init_terraform
    plan_deployment

    # Ask for confirmation before applying
    read -p "Do you want to apply this plan? (yes/no): " -r
    if [[ $REPLY =~ ^yes$ ]]; then
        apply_deployment
        get_credentials
    else
        log_info "Deployment cancelled. Plan saved as: deployment.tfplan"
    fi

    cleanup
    log_info "Deployment process completed!"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"