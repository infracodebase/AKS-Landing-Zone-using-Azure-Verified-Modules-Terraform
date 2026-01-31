#!/bin/bash

# AWS EKS Landing Zone - CloudFormation Destruction Script
# This script safely destroys the EKS landing zone infrastructure in reverse order

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values - override with environment variables
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
CLUSTER_NAME="${CLUSTER_NAME:-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_PREFIX="${STACK_PREFIX:-${CLUSTER_NAME}-${ENVIRONMENT_NAME}}"

# CloudFormation stack names (in reverse deletion order)
EKS_STACK_NAME="${STACK_PREFIX}-eks"
ECR_STACK_NAME="${STACK_PREFIX}-ecr"
IAM_STACK_NAME="${STACK_PREFIX}-iam"
ENDPOINTS_STACK_NAME="${STACK_PREFIX}-endpoints"
VPC_STACK_NAME="${STACK_PREFIX}-vpc"

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
}

# Function to check if stack exists
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null
}

# Function to get stack status
get_stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "DOES_NOT_EXIST"
}

# Function to list existing stacks
list_existing_stacks() {
    log_info "Checking for existing stacks..."

    local stacks=(
        "$EKS_STACK_NAME"
        "$ECR_STACK_NAME"
        "$IAM_STACK_NAME"
        "$ENDPOINTS_STACK_NAME"
        "$VPC_STACK_NAME"
    )

    local existing_stacks=()

    for stack in "${stacks[@]}"; do
        if stack_exists "$stack"; then
            local status=$(get_stack_status "$stack")
            existing_stacks+=("$stack ($status)")
            echo "  ✓ $stack - $status"
        else
            echo "  ✗ $stack - Does not exist"
        fi
    done

    if [[ ${#existing_stacks[@]} -eq 0 ]]; then
        log_warning "No stacks found to delete."
        exit 0
    fi

    return ${#existing_stacks[@]}
}

# Function to empty S3 bucket before deletion
empty_s3_bucket() {
    local bucket_name="$1"

    log_info "Checking if S3 bucket $bucket_name exists..."

    if aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
        log_info "Emptying S3 bucket: $bucket_name"

        # Delete all versions and delete markers
        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
            --region "$AWS_REGION" 2>/dev/null || true

        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
            --region "$AWS_REGION" 2>/dev/null || true

        # Delete remaining objects
        aws s3 rm "s3://$bucket_name" --recursive --region "$AWS_REGION" 2>/dev/null || true

        log_success "S3 bucket $bucket_name emptied"
    else
        log_info "S3 bucket $bucket_name does not exist or is not accessible"
    fi
}

# Function to clean up ECR repositories
cleanup_ecr_repositories() {
    log_info "Cleaning up ECR repositories..."

    local repo_names=(
        "${CLUSTER_NAME}-${ENVIRONMENT_NAME}"
        "${CLUSTER_NAME}-${ENVIRONMENT_NAME}-base"
    )

    for repo_name in "${repo_names[@]}"; do
        if aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" &>/dev/null; then
            log_info "Deleting all images in ECR repository: $repo_name"

            # List and delete all images
            local images=$(aws ecr list-images --repository-name "$repo_name" --region "$AWS_REGION" --query 'imageIds[*]' --output json)

            if [[ "$images" != "[]" ]]; then
                aws ecr batch-delete-image \
                    --repository-name "$repo_name" \
                    --image-ids "$images" \
                    --region "$AWS_REGION" >/dev/null
                log_success "All images deleted from repository: $repo_name"
            else
                log_info "No images found in repository: $repo_name"
            fi
        else
            log_info "ECR repository $repo_name does not exist"
        fi
    done
}

# Function to delete OIDC provider
cleanup_oidc_provider() {
    log_info "Cleaning up OIDC provider..."

    local cluster_name="${CLUSTER_NAME}-${ENVIRONMENT_NAME}"

    # Try to get OIDC issuer URL from the cluster if it still exists
    local oidc_issuer_url=""
    if aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" &>/dev/null; then
        oidc_issuer_url=$(aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" --query "cluster.identity.oidc.issuer" --output text 2>/dev/null || echo "")
    fi

    # If we couldn't get it from the cluster, try to find it by pattern
    if [[ -z "$oidc_issuer_url" ]]; then
        oidc_issuer_url="https://oidc.eks.${AWS_REGION}.amazonaws.com/id/"
    fi

    local oidc_issuer_host=$(echo "$oidc_issuer_url" | sed 's/https:\/\///')

    # Find and delete OIDC provider
    local existing_arn=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '${oidc_issuer_host}')].Arn" --output text 2>/dev/null || echo "")

    if [[ -n "$existing_arn" ]] && [[ "$existing_arn" != "None" ]]; then
        log_info "Deleting OIDC provider: $existing_arn"
        aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$existing_arn" 2>/dev/null || true
        log_success "OIDC provider deleted"
    else
        log_info "No OIDC provider found for cleanup"
    fi
}

# Function to delete a CloudFormation stack
delete_stack() {
    local stack_name="$1"
    local max_wait="${2:-30}" # Maximum wait time in minutes

    if ! stack_exists "$stack_name"; then
        log_info "Stack $stack_name does not exist, skipping..."
        return 0
    fi

    local status=$(get_stack_status "$stack_name")

    if [[ "$status" == *"IN_PROGRESS"* ]]; then
        log_warning "Stack $stack_name is currently $status. Waiting for completion..."
        aws cloudformation wait stack-deploy-complete --stack-name "$stack_name" --region "$AWS_REGION" 2>/dev/null || true
    fi

    log_info "Deleting stack: $stack_name"

    if aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION"; then
        log_info "Waiting for stack $stack_name deletion to complete (max ${max_wait} minutes)..."

        # Wait for stack deletion with timeout
        local wait_time=0
        while stack_exists "$stack_name" && [[ $wait_time -lt $((max_wait * 60)) ]]; do
            sleep 30
            wait_time=$((wait_time + 30))

            local current_status=$(get_stack_status "$stack_name")
            if [[ "$current_status" == "DELETE_FAILED" ]]; then
                log_error "Stack deletion failed: $stack_name"

                # Show delete failed resources
                log_info "Resources that failed to delete:"
                aws cloudformation describe-stack-events \
                    --stack-name "$stack_name" \
                    --region "$AWS_REGION" \
                    --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].{Resource:LogicalResourceId,Reason:ResourceStatusReason}" \
                    --output table 2>/dev/null || true

                return 1
            fi

            log_info "Stack deletion in progress... (${wait_time}s elapsed)"
        done

        if stack_exists "$stack_name"; then
            log_warning "Stack deletion timeout reached for $stack_name"
            return 1
        else
            log_success "Stack $stack_name deleted successfully"
            return 0
        fi
    else
        log_error "Failed to initiate deletion of stack $stack_name"
        return 1
    fi
}

# Function to force delete stuck stacks
force_delete_stack() {
    local stack_name="$1"

    log_warning "Attempting to force delete stack: $stack_name"

    # Get resources to retain (skip deletion)
    local resources_to_retain=$(aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --query "StackResourceSummaries[?ResourceStatus=='DELETE_FAILED'].LogicalResourceId" \
        --output text 2>/dev/null || echo "")

    if [[ -n "$resources_to_retain" ]]; then
        log_info "Retaining failed resources: $resources_to_retain"

        # Convert to array for CloudFormation parameter
        local retain_resources=()
        IFS=$'\t' read -ra ADDR <<< "$resources_to_retain"
        for resource in "${ADDR[@]}"; do
            retain_resources+=("$resource")
        done

        # Delete stack while retaining failed resources
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --retain-resources "${retain_resources[@]}" \
            --region "$AWS_REGION" || true
    fi
}

# Main deletion function
main() {
    log_info "Starting AWS EKS Landing Zone destruction..."

    # Pre-deletion checks
    check_aws_cli

    # List existing stacks
    if ! list_existing_stacks; then
        exit 0
    fi

    # Confirm destruction
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION ⚠️"
    echo ""
    echo "This will permanently delete the following infrastructure:"
    echo "- EKS cluster and all workloads"
    echo "- ECR repositories and container images"
    echo "- IAM roles and policies"
    echo "- VPC endpoints"
    echo "- VPC and all networking resources"
    echo "- S3 buckets and contents"
    echo "- CloudWatch logs and metrics"
    echo "- Secrets Manager secrets"
    echo "- KMS keys"
    echo ""
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    log_error "This action CANNOT be undone!"
    echo ""
    read -p "Type 'DELETE' to confirm destruction: " -r

    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Destruction cancelled."
        exit 0
    fi

    echo ""
    log_info "Starting destruction process..."

    # Pre-deletion cleanup
    log_info "Performing pre-deletion cleanup..."

    # Empty S3 bucket if it exists
    local s3_bucket_name="${CLUSTER_NAME}-${ENVIRONMENT_NAME}-artifacts-$(aws sts get-caller-identity --query Account --output text)"
    empty_s3_bucket "$s3_bucket_name"

    # Clean up ECR repositories
    cleanup_ecr_repositories

    # Delete stacks in reverse order
    local stacks=(
        "$EKS_STACK_NAME"
        "$ECR_STACK_NAME"
        "$IAM_STACK_NAME"
        "$ENDPOINTS_STACK_NAME"
        "$VPC_STACK_NAME"
    )

    local failed_stacks=()

    for stack in "${stacks[@]}"; do
        if stack_exists "$stack"; then
            if ! delete_stack "$stack" 25; then
                failed_stacks+=("$stack")

                # Try force delete for certain stacks
                if [[ "$stack" == "$VPC_STACK_NAME" ]] || [[ "$stack" == "$ECR_STACK_NAME" ]]; then
                    log_warning "Attempting force delete for $stack"
                    force_delete_stack "$stack"
                fi
            fi
        fi
    done

    # Clean up OIDC provider
    cleanup_oidc_provider

    # Report results
    echo ""
    if [[ ${#failed_stacks[@]} -eq 0 ]]; then
        log_success "All stacks deleted successfully!"
    else
        log_warning "Some stacks failed to delete:"
        for failed_stack in "${failed_stacks[@]}"; do
            echo "  ✗ $failed_stack"
        done
        echo ""
        log_info "You may need to manually clean up remaining resources."
        log_info "Check the AWS Console for any remaining resources."
    fi

    echo ""
    log_info "Destruction process completed."
}

# Trap to handle script interruption
trap 'log_error "Destruction interrupted."; exit 1' INT TERM

# Show usage information
show_usage() {
    echo "AWS EKS Landing Zone - CloudFormation Destruction Script"
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
EKS_STACK_NAME="${STACK_PREFIX}-eks"
ECR_STACK_NAME="${STACK_PREFIX}-ecr"
IAM_STACK_NAME="${STACK_PREFIX}-iam"
ENDPOINTS_STACK_NAME="${STACK_PREFIX}-endpoints"
VPC_STACK_NAME="${STACK_PREFIX}-vpc"

# Run main function
main "$@"