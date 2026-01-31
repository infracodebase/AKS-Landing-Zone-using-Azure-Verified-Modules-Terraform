#!/bin/bash

# AWS EKS Landing Zone - Terraform Deployment Script
# This script deploys the complete EKS landing zone infrastructure using Terraform

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Default values - override with environment variables
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
CLUSTER_NAME="${CLUSTER_NAME:-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
TF_VAR_FILE="${TF_VAR_FILE:-terraform.tfvars}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform >= 1.9.0"
        exit 1
    fi

    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
    log_info "Terraform version: $tf_version"

    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi

    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    local current_region
    current_region=$(aws configure get region || echo "us-east-1")

    log_success "AWS CLI configured for account: $account_id in region: $current_region"

    # Check if kubectl is installed (optional but recommended)
    if command -v kubectl &> /dev/null; then
        local kubectl_version
        kubectl_version=$(kubectl version --client -o yaml | grep gitVersion | awk '{print $2}')
        log_info "kubectl version: $kubectl_version"
    else
        log_warning "kubectl is not installed. You'll need it to manage the cluster after deployment"
    fi
}

# Function to setup Terraform variables
setup_terraform_vars() {
    log_info "Setting up Terraform variables..."

    cd "$TERRAFORM_DIR"

    # Check if terraform.tfvars exists
    if [[ ! -f "$TF_VAR_FILE" ]]; then
        if [[ -f "terraform.tfvars.example" ]]; then
            log_info "Creating $TF_VAR_FILE from example..."
            cp terraform.tfvars.example "$TF_VAR_FILE"

            # Update with environment variables if provided
            if [[ -n "${ENVIRONMENT_NAME:-}" ]]; then
                sed -i.bak "s/environment = \"dev\"/environment = \"$ENVIRONMENT_NAME\"/" "$TF_VAR_FILE"
            fi
            if [[ -n "${CLUSTER_NAME:-}" ]]; then
                sed -i.bak "s/cluster_name = \"eks-cluster\"/cluster_name = \"$CLUSTER_NAME\"/" "$TF_VAR_FILE"
            fi
            if [[ -n "${AWS_REGION:-}" ]]; then
                sed -i.bak "s/aws_region = \"us-east-1\"/aws_region = \"$AWS_REGION\"/" "$TF_VAR_FILE"
            fi

            # Remove backup files
            rm -f "${TF_VAR_FILE}.bak"

            log_warning "Please review and update $TF_VAR_FILE with your specific values"
            log_info "Key variables to review:"
            echo "  - VPC CIDR blocks"
            echo "  - Node instance types and sizes"
            echo "  - Additional tags"
            echo ""
            read -p "Continue with current values in $TF_VAR_FILE? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Please update $TF_VAR_FILE and run the script again"
                exit 0
            fi
        else
            log_error "No $TF_VAR_FILE found and no example file available"
            exit 1
        fi
    else
        log_success "Using existing $TF_VAR_FILE"
    fi
}

# Function to initialize Terraform
terraform_init() {
    log_info "Initializing Terraform..."

    cd "$TERRAFORM_DIR"

    # Initialize Terraform
    terraform init -upgrade

    log_success "Terraform initialized successfully"
}

# Function to plan Terraform deployment
terraform_plan() {
    log_info "Creating Terraform plan..."

    cd "$TERRAFORM_DIR"

    # Create plan
    terraform plan -var-file="$TF_VAR_FILE" -out=tfplan

    log_success "Terraform plan created successfully"
}

# Function to apply Terraform deployment
terraform_apply() {
    log_info "Applying Terraform plan..."

    cd "$TERRAFORM_DIR"

    # Apply the plan
    terraform apply tfplan

    log_success "Terraform deployment completed successfully"
}

# Function to display deployment outputs
show_outputs() {
    log_info "Retrieving deployment outputs..."

    cd "$TERRAFORM_DIR"

    echo ""
    echo "=== Deployment Summary ==="
    terraform output -json deployment_summary | jq -r '.cluster | "Cluster: \(.name) (v\(.version)) in \(.region)"'
    echo ""

    # Get cluster information
    local cluster_name
    cluster_name=$(terraform output -raw cluster_name)
    local cluster_endpoint
    cluster_endpoint=$(terraform output -raw cluster_endpoint)
    local aws_region
    aws_region=$(terraform output -raw aws_region || echo "$AWS_REGION")

    echo "=== Cluster Access ==="
    echo "Cluster Name: $cluster_name"
    echo "Cluster Endpoint: $cluster_endpoint"
    echo ""
    echo "To configure kubectl:"
    echo "aws eks update-kubeconfig --region $aws_region --name $cluster_name"
    echo ""
    echo "To verify cluster access:"
    echo "kubectl get nodes"
    echo "kubectl get pods -A"
    echo ""

    # Display resource URLs
    echo "=== Management URLs ==="

    # CloudWatch Dashboard
    local dashboard_url
    dashboard_url=$(terraform output -raw cloudwatch_dashboard_url)
    echo "CloudWatch Dashboard: $dashboard_url"

    # ECR Repositories
    echo ""
    echo "=== Container Repositories ==="
    terraform output -json ecr_repository_urls | jq -r 'to_entries[] | "\(.key): \(.value)"'

    echo ""
    echo "=== Next Steps ==="
    echo "1. Configure kubectl access to your cluster"
    echo "2. Install additional Kubernetes tools (Helm charts, operators)"
    echo "3. Deploy your applications"
    echo "4. Set up CI/CD pipelines to use ECR repositories"
    echo "5. Configure monitoring and alerting"
    echo ""
    echo "For troubleshooting, check CloudWatch Logs:"
    terraform output -json | jq -r '.cluster_log_group_name.value // empty' | while read -r log_group; do
        if [[ -n "$log_group" ]]; then
            echo "aws logs tail '$log_group' --region $aws_region --follow"
        fi
    done
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."

    cd "$TERRAFORM_DIR"

    # Check if all required outputs are available
    local required_outputs=("cluster_name" "cluster_endpoint" "vpc_id")
    local missing_outputs=()

    for output in "${required_outputs[@]}"; do
        if ! terraform output "$output" &>/dev/null; then
            missing_outputs+=("$output")
        fi
    done

    if [[ ${#missing_outputs[@]} -gt 0 ]]; then
        log_error "Missing required outputs: ${missing_outputs[*]}"
        return 1
    fi

    # Try to get cluster status
    local cluster_name
    cluster_name=$(terraform output -raw cluster_name)
    local aws_region
    aws_region=$(terraform output -raw aws_region || echo "$AWS_REGION")

    log_info "Checking cluster status..."
    local cluster_status
    cluster_status=$(aws eks describe-cluster --name "$cluster_name" --region "$aws_region" --query 'cluster.status' --output text)

    if [[ "$cluster_status" == "ACTIVE" ]]; then
        log_success "Cluster is active and ready"
    else
        log_warning "Cluster status: $cluster_status"
    fi

    # Check node groups
    log_info "Checking node groups..."
    local node_groups
    node_groups=$(aws eks list-nodegroups --cluster-name "$cluster_name" --region "$aws_region" --query 'nodegroups' --output json)
    local node_group_count
    node_group_count=$(echo "$node_groups" | jq 'length')

    if [[ "$node_group_count" -ge 2 ]]; then
        log_success "$node_group_count node groups found"
    else
        log_warning "Only $node_group_count node groups found (expected at least 2)"
    fi

    log_success "Deployment validation completed"
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_warning "Deployment failed. Cleaning up..."

    cd "$TERRAFORM_DIR"

    # Remove the plan file
    rm -f tfplan

    log_info "Cleanup completed. You may need to manually clean up any partially created resources"
}

# Main deployment function
main() {
    log_info "Starting AWS EKS Landing Zone deployment with Terraform..."

    # Pre-deployment checks
    check_prerequisites
    setup_terraform_vars

    # Confirm deployment
    echo ""
    log_warning "This will deploy the following infrastructure:"
    echo "- VPC with public/private subnets across multiple AZs"
    echo "- VPC endpoints for private AWS service access"
    echo "- EKS cluster with private API endpoint"
    echo "- System and user node groups with auto-scaling"
    echo "- ECR repositories for container images"
    echo "- Secrets Manager for application secrets"
    echo "- CloudWatch logging and monitoring"
    echo "- KMS keys for encryption"
    echo "- IAM roles for workload identity (IRSA)"
    echo ""
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi

    echo ""
    log_info "Starting deployment process..."

    # Deployment steps
    terraform_init
    terraform_plan
    terraform_apply
    validate_deployment
    show_outputs

    echo ""
    log_success "AWS EKS Landing Zone deployed successfully!"
}

# Function to show usage
show_usage() {
    echo "AWS EKS Landing Zone - Terraform Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment     Environment name (default: dev)"
    echo "  -c, --cluster         Cluster name (default: eks-cluster)"
    echo "  -r, --region          AWS region (default: us-east-1)"
    echo "  -f, --var-file        Terraform variables file (default: terraform.tfvars)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  ENVIRONMENT_NAME      Environment name (dev, staging, prod)"
    echo "  CLUSTER_NAME          EKS cluster name"
    echo "  AWS_REGION            AWS region for deployment"
    echo "  TF_VAR_FILE          Terraform variables file"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod -c production-eks -r us-west-2"
    echo "  ENVIRONMENT_NAME=staging CLUSTER_NAME=test-cluster $0"
}

# Trap to handle script interruption
trap cleanup_on_failure ERR INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT_NAME="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--var-file)
            TF_VAR_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Export environment variables for Terraform
export TF_VAR_environment="$ENVIRONMENT_NAME"
export TF_VAR_cluster_name="$CLUSTER_NAME"
export TF_VAR_aws_region="$AWS_REGION"

# Run main function
main "$@"