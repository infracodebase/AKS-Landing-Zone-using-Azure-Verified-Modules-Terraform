#!/bin/bash

# AWS EKS Landing Zone - CloudFormation Deployment Script
# This script deploys the complete EKS landing zone infrastructure using CloudFormation

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CF_DIR="$PROJECT_ROOT/cloudformation"

# Default values - override with environment variables
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
CLUSTER_NAME="${CLUSTER_NAME:-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_PREFIX="${STACK_PREFIX:-${CLUSTER_NAME}-${ENVIRONMENT_NAME}}"

# CloudFormation stack names
VPC_STACK_NAME="${STACK_PREFIX}-vpc"
ENDPOINTS_STACK_NAME="${STACK_PREFIX}-endpoints"
IAM_STACK_NAME="${STACK_PREFIX}-iam"
ECR_STACK_NAME="${STACK_PREFIX}-ecr"
EKS_STACK_NAME="${STACK_PREFIX}-eks"

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

# Function to check if AWS CLI is configured
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi

    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local current_region=$(aws configure get region)

    log_success "AWS CLI configured for account: $account_id in region: $current_region"

    if [[ "$current_region" != "$AWS_REGION" ]]; then
        log_warning "Current AWS region ($current_region) differs from target region ($AWS_REGION)"
        read -p "Continue with region $AWS_REGION? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled."
            exit 0
        fi
    fi
}

# Function to validate CloudFormation templates
validate_templates() {
    log_info "Validating CloudFormation templates..."

    local templates=(
        "01-vpc-network.yaml"
        "02-vpc-endpoints.yaml"
        "03-iam-roles.yaml"
        "04-ecr-secrets.yaml"
        "05-eks-cluster.yaml"
    )

    for template in "${templates[@]}"; do
        local template_path="$CF_DIR/$template"
        if [[ ! -f "$template_path" ]]; then
            log_error "Template not found: $template_path"
            exit 1
        fi

        log_info "Validating $template..."
        if aws cloudformation validate-template --template-body file://"$template_path" --region "$AWS_REGION" > /dev/null; then
            log_success "Template $template is valid"
        else
            log_error "Template $template is invalid"
            exit 1
        fi
    done
}

# Function to deploy a CloudFormation stack
deploy_stack() {
    local stack_name="$1"
    local template_file="$2"
    local parameters="$3"
    local capabilities="${4:-}"

    log_info "Deploying stack: $stack_name"

    local template_path="$CF_DIR/$template_file"
    local cmd="aws cloudformation deploy"
    cmd="$cmd --template-file $template_path"
    cmd="$cmd --stack-name $stack_name"
    cmd="$cmd --region $AWS_REGION"

    if [[ -n "$parameters" ]]; then
        cmd="$cmd --parameter-overrides $parameters"
    fi

    if [[ -n "$capabilities" ]]; then
        cmd="$cmd --capabilities $capabilities"
    fi

    cmd="$cmd --tags"
    cmd="$cmd Environment=$ENVIRONMENT_NAME"
    cmd="$cmd Cluster=$CLUSTER_NAME"
    cmd="$cmd ManagedBy=CloudFormation"
    cmd="$cmd Project=EKS-Landing-Zone"

    if eval "$cmd"; then
        log_success "Stack $stack_name deployed successfully"

        # Wait for stack to be completely ready
        log_info "Waiting for stack $stack_name to be ready..."
        aws cloudformation wait stack-deploy-complete --stack-name "$stack_name" --region "$AWS_REGION"
        log_success "Stack $stack_name is ready"
    else
        log_error "Failed to deploy stack $stack_name"
        exit 1
    fi
}

# Function to check if stack exists
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null
}

# Function to get stack output
get_stack_output() {
    local stack_name="$1"
    local output_key="$2"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "Account ID: $(aws sts get-caller-identity --query Account --output text)"
    echo ""
    echo "Deployed Stacks:"
    echo "- VPC: $VPC_STACK_NAME"
    echo "- VPC Endpoints: $ENDPOINTS_STACK_NAME"
    echo "- IAM Roles: $IAM_STACK_NAME"
    echo "- ECR & Secrets: $ECR_STACK_NAME"
    echo "- EKS Cluster: $EKS_STACK_NAME"
    echo ""

    if stack_exists "$EKS_STACK_NAME"; then
        local cluster_endpoint=$(get_stack_output "$EKS_STACK_NAME" "ClusterEndpoint")
        local oidc_issuer=$(get_stack_output "$EKS_STACK_NAME" "OIDCIssuerURL")

        echo "Cluster Information:"
        echo "- Endpoint: $cluster_endpoint"
        echo "- OIDC Issuer: $oidc_issuer"
        echo ""
        echo "To configure kubectl:"
        echo "aws eks update-kubeconfig --region $AWS_REGION --name ${CLUSTER_NAME}-${ENVIRONMENT_NAME}"
        echo ""
        echo "To verify cluster access:"
        echo "kubectl get nodes"
    fi
}

# Function to deploy OIDC provider (if needed)
deploy_oidc_provider() {
    log_info "Setting up OIDC Identity Provider..."

    local cluster_name="${CLUSTER_NAME}-${ENVIRONMENT_NAME}"
    local oidc_issuer_url=$(aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" --query "cluster.identity.oidc.issuer" --output text)
    local oidc_issuer_host=$(echo "$oidc_issuer_url" | sed 's/https:\/\///')

    # Check if OIDC provider already exists
    local existing_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$oidc_issuer_host')].Arn" --output text)

    if [[ -n "$existing_arn" ]]; then
        log_info "OIDC provider already exists: $existing_arn"
    else
        log_info "Creating OIDC provider for $oidc_issuer_url"

        # Get the certificate thumbprint
        local thumbprint=$(openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com -showcerts -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 </dev/null 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | sed 's/://g' | awk -F= '{print tolower($2)}')

        aws iam create-open-id-connect-provider \
            --url "$oidc_issuer_url" \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list "$thumbprint" \
            --region "$AWS_REGION"

        log_success "OIDC provider created successfully"
    fi
}

# Main deployment function
main() {
    log_info "Starting AWS EKS Landing Zone deployment..."

    # Pre-deployment checks
    check_aws_cli
    validate_templates

    # Confirm deployment
    echo ""
    log_warning "This will deploy the following infrastructure:"
    echo "- VPC with public/private subnets across 2 AZs"
    echo "- VPC endpoints for private AWS service access"
    echo "- IAM roles for EKS cluster and workloads"
    echo "- ECR repositories and secrets management"
    echo "- EKS cluster with system and user node groups"
    echo "- CloudWatch logging and monitoring"
    echo ""
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled."
        exit 0
    fi

    echo ""
    log_info "Starting deployment process..."

    # Deploy VPC and networking (Step 1)
    deploy_stack "$VPC_STACK_NAME" "01-vpc-network.yaml" \
        "EnvironmentName=$ENVIRONMENT_NAME ClusterName=$CLUSTER_NAME"

    # Deploy VPC endpoints (Step 2)
    deploy_stack "$ENDPOINTS_STACK_NAME" "02-vpc-endpoints.yaml" \
        "VPCStackName=$VPC_STACK_NAME EnvironmentName=$ENVIRONMENT_NAME ClusterName=$CLUSTER_NAME"

    # Deploy IAM roles (Step 3)
    deploy_stack "$IAM_STACK_NAME" "03-iam-roles.yaml" \
        "EnvironmentName=$ENVIRONMENT_NAME ClusterName=$CLUSTER_NAME" \
        "CAPABILITY_NAMED_IAM"

    # Deploy ECR and secrets (Step 4)
    deploy_stack "$ECR_STACK_NAME" "04-ecr-secrets.yaml" \
        "VPCStackName=$VPC_STACK_NAME EnvironmentName=$ENVIRONMENT_NAME ClusterName=$CLUSTER_NAME"

    # Deploy EKS cluster (Step 5)
    deploy_stack "$EKS_STACK_NAME" "05-eks-cluster.yaml" \
        "VPCStackName=$VPC_STACK_NAME IAMStackName=$IAM_STACK_NAME ECRStackName=$ECR_STACK_NAME EndpointsStackName=$ENDPOINTS_STACK_NAME EnvironmentName=$ENVIRONMENT_NAME ClusterName=$CLUSTER_NAME"

    # Setup OIDC provider for service accounts
    deploy_oidc_provider

    # Update IAM stack with OIDC issuer URL for service account roles
    local oidc_issuer_url=$(get_stack_output "$EKS_STACK_NAME" "OIDCIssuerURL")
    local oidc_issuer_host=$(echo "$oidc_issuer_url" | sed 's/https:\/\///')

    log_info "Updating IAM stack with OIDC issuer URL..."
    deploy_stack "$IAM_STACK_NAME" "03-iam-roles.yaml" \
        "EnvironmentName=$ENVIRONMENT_NAME ClusterName=$CLUSTER_NAME EKSOIDCIssuerURL=$oidc_issuer_host" \
        "CAPABILITY_NAMED_IAM"

    # Display deployment summary
    echo ""
    log_success "AWS EKS Landing Zone deployed successfully!"
    echo ""
    display_summary
}

# Trap to handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Show usage information
show_usage() {
    echo "AWS EKS Landing Zone - CloudFormation Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment     Environment name (default: dev)"
    echo "  -c, --cluster         Cluster name (default: eks-cluster)"
    echo "  -r, --region          AWS region (default: us-east-1)"
    echo "  -p, --prefix          Stack name prefix (default: CLUSTER-ENVIRONMENT)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  ENVIRONMENT_NAME      Environment name (dev, staging, prod)"
    echo "  CLUSTER_NAME          EKS cluster name"
    echo "  AWS_REGION            AWS region for deployment"
    echo "  STACK_PREFIX          CloudFormation stack name prefix"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod -c acme-eks -r us-west-2"
    echo "  ENVIRONMENT_NAME=staging CLUSTER_NAME=test-cluster $0"
}

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
        -p|--prefix)
            STACK_PREFIX="$2"
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

# Update derived values
VPC_STACK_NAME="${STACK_PREFIX}-vpc"
ENDPOINTS_STACK_NAME="${STACK_PREFIX}-endpoints"
IAM_STACK_NAME="${STACK_PREFIX}-iam"
ECR_STACK_NAME="${STACK_PREFIX}-ecr"
EKS_STACK_NAME="${STACK_PREFIX}-eks"

# Run main function
main "$@"