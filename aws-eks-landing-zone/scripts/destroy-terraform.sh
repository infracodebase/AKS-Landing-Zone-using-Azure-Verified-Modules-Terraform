#!/bin/bash

# AWS EKS Landing Zone - Terraform Destruction Script
# This script safely destroys the EKS landing zone infrastructure

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
    log_success "AWS CLI configured for account: $account_id"

    # Check if Terraform directory exists
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        log_error "Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi

    # Check if Terraform state exists
    cd "$TERRAFORM_DIR"
    if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
        log_warning "No local Terraform state found. Checking for remote state..."
        if ! terraform show &>/dev/null; then
            log_error "No Terraform state found. Nothing to destroy"
            exit 1
        fi
    fi
}

# Function to show current infrastructure
show_current_infrastructure() {
    log_info "Retrieving current infrastructure state..."

    cd "$TERRAFORM_DIR"

    if terraform show -json &>/dev/null; then
        echo ""
        echo "=== Current Infrastructure ==="

        # Try to get cluster information
        if terraform output cluster_name &>/dev/null; then
            local cluster_name
            cluster_name=$(terraform output -raw cluster_name)
            echo "EKS Cluster: $cluster_name"

            # Get cluster status
            local cluster_status=""
            if aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" &>/dev/null; then
                cluster_status=$(aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" --query 'cluster.status' --output text)
                echo "Cluster Status: $cluster_status"
            fi

            # Get node groups
            local node_groups
            if node_groups=$(aws eks list-nodegroups --cluster-name "$cluster_name" --region "$AWS_REGION" --query 'nodegroups' --output json 2>/dev/null); then
                local node_group_count
                node_group_count=$(echo "$node_groups" | jq 'length')
                echo "Node Groups: $node_group_count"
            fi
        fi

        # Show VPC information
        if terraform output vpc_id &>/dev/null; then
            local vpc_id
            vpc_id=$(terraform output -raw vpc_id)
            echo "VPC ID: $vpc_id"
        fi

        # Show ECR repositories
        if terraform output ecr_repository_urls &>/dev/null; then
            local repo_count
            repo_count=$(terraform output -json ecr_repository_urls | jq 'length')
            echo "ECR Repositories: $repo_count"
        fi

        # Show S3 buckets
        if terraform output cluster_artifacts_bucket_name &>/dev/null; then
            local bucket_name
            bucket_name=$(terraform output -raw cluster_artifacts_bucket_name)
            echo "S3 Artifacts Bucket: $bucket_name"
        fi

        echo ""
    else
        log_warning "Could not retrieve current state information"
    fi
}

# Function to perform pre-destruction cleanup
pre_destruction_cleanup() {
    log_info "Performing pre-destruction cleanup..."

    cd "$TERRAFORM_DIR"

    # Get cluster name if available
    local cluster_name=""
    if terraform output cluster_name &>/dev/null; then
        cluster_name=$(terraform output -raw cluster_name)
    fi

    # Clean up LoadBalancer services that might create external resources
    if [[ -n "$cluster_name" ]] && aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" &>/dev/null; then
        log_info "Checking for LoadBalancer services in cluster..."

        # Try to configure kubectl
        if command -v kubectl &>/dev/null; then
            if aws eks update-kubeconfig --region "$AWS_REGION" --name "$cluster_name" &>/dev/null; then
                log_info "Configured kubectl for cleanup operations"

                # Delete LoadBalancer services
                local lb_services
                lb_services=$(kubectl get services --all-namespaces -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' 2>/dev/null || echo "")
                if [[ -n "$lb_services" ]]; then
                    log_warning "Found LoadBalancer services. These may create external AWS resources."
                    log_info "Deleting LoadBalancer services..."
                    kubectl delete services --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found=true || true
                    sleep 30 # Wait for AWS load balancers to be cleaned up
                fi

                # Delete Ingress resources
                log_info "Deleting Ingress resources..."
                kubectl delete ingress --all-namespaces --all --ignore-not-found=true || true
            else
                log_warning "Could not configure kubectl for pre-cleanup"
            fi
        else
            log_warning "kubectl not available for pre-cleanup"
        fi
    fi

    # Empty S3 buckets before destruction
    if terraform output cluster_artifacts_bucket_name &>/dev/null; then
        local bucket_name
        bucket_name=$(terraform output -raw cluster_artifacts_bucket_name)

        log_info "Emptying S3 bucket: $bucket_name"

        # Check if bucket exists
        if aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
            # Delete all objects and versions
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

            log_success "S3 bucket emptied"
        else
            log_info "S3 bucket $bucket_name not found or not accessible"
        fi
    fi

    # Clean up ECR repositories
    if terraform output ecr_repository_urls &>/dev/null; then
        log_info "Cleaning up ECR repository images..."

        terraform output -json ecr_repository_urls | jq -r 'keys[]' | while read -r repo_key; do
            local repo_name
            repo_name=$(terraform output -json ecr_repository_urls | jq -r ".\"$repo_key\"" | sed 's|.*/||')

            if aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" &>/dev/null; then
                log_info "Deleting images in ECR repository: $repo_name"

                # List and delete all images
                local images
                images=$(aws ecr list-images --repository-name "$repo_name" --region "$AWS_REGION" --query 'imageIds[*]' --output json)

                if [[ "$images" != "[]" ]]; then
                    aws ecr batch-delete-image \
                        --repository-name "$repo_name" \
                        --image-ids "$images" \
                        --region "$AWS_REGION" >/dev/null || true
                    log_success "Images deleted from repository: $repo_name"
                fi
            fi
        done
    fi

    log_success "Pre-destruction cleanup completed"
}

# Function to create destruction plan
terraform_plan_destroy() {
    log_info "Creating Terraform destruction plan..."

    cd "$TERRAFORM_DIR"

    # Create destroy plan
    terraform plan -destroy -var-file="$TF_VAR_FILE" -out=destroy.tfplan

    log_success "Terraform destruction plan created"
}

# Function to execute destruction
terraform_destroy() {
    log_info "Executing Terraform destruction..."

    cd "$TERRAFORM_DIR"

    # Apply the destruction plan
    terraform apply destroy.tfplan

    # Clean up plan file
    rm -f destroy.tfplan

    log_success "Terraform destruction completed"
}

# Function to verify destruction
verify_destruction() {
    log_info "Verifying infrastructure destruction..."

    cd "$TERRAFORM_DIR"

    # Check if any resources remain in state
    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l)

    if [[ "$resource_count" -eq 0 ]]; then
        log_success "All resources successfully destroyed"
    else
        log_warning "$resource_count resources remain in state"
        echo "Remaining resources:"
        terraform state list
    fi

    # Check for any remaining AWS resources that might not be in state
    log_info "Checking for remaining AWS resources..."

    # Try to check if cluster still exists (in case of partial failure)
    local cluster_name="${CLUSTER_NAME}-${ENVIRONMENT_NAME}"
    if aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" &>/dev/null; then
        log_warning "EKS cluster $cluster_name still exists"
    fi

    # Check for any remaining ECR repositories with our naming pattern
    local remaining_repos
    remaining_repos=$(aws ecr describe-repositories --region "$AWS_REGION" \
        --query "repositories[?starts_with(repositoryName, '${CLUSTER_NAME}-${ENVIRONMENT_NAME}')].repositoryName" \
        --output text 2>/dev/null || echo "")

    if [[ -n "$remaining_repos" ]] && [[ "$remaining_repos" != "None" ]]; then
        log_warning "Remaining ECR repositories: $remaining_repos"
    fi

    log_info "Destruction verification completed"
}

# Function to show post-destruction summary
show_destruction_summary() {
    echo ""
    echo "=== Destruction Summary ==="
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    echo "The following resources were destroyed:"
    echo "- EKS cluster and node groups"
    echo "- VPC and all networking components"
    echo "- ECR repositories (with images)"
    echo "- Secrets Manager secrets"
    echo "- S3 artifacts bucket (with contents)"
    echo "- KMS keys"
    echo "- IAM roles and policies"
    echo "- CloudWatch log groups and dashboards"
    echo "- SNS topics"
    echo ""
    echo "Note: Some AWS resources may take additional time to be fully removed"
    echo "Check the AWS console to verify complete cleanup if needed"
}

# Main destruction function
main() {
    log_info "Starting AWS EKS Landing Zone destruction..."

    # Pre-destruction checks
    check_prerequisites
    show_current_infrastructure

    # Confirm destruction
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION ⚠️"
    echo ""
    echo "This will permanently delete ALL infrastructure resources including:"
    echo "- EKS cluster and all workloads"
    echo "- All container images in ECR repositories"
    echo "- All data in S3 buckets"
    echo "- All secrets and configuration"
    echo "- All logs and monitoring data"
    echo "- VPC and networking infrastructure"
    echo "- All KMS keys"
    echo ""
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    log_error "This action CANNOT be undone!"
    echo ""
    echo "Type the full cluster name to confirm:"
    read -p "Cluster name (${CLUSTER_NAME}-${ENVIRONMENT_NAME}): " -r

    if [[ "$REPLY" != "${CLUSTER_NAME}-${ENVIRONMENT_NAME}" ]]; then
        log_info "Destruction cancelled - cluster name mismatch"
        exit 0
    fi

    echo ""
    read -p "Type 'DESTROY' to proceed with destruction: " -r
    if [[ "$REPLY" != "DESTROY" ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi

    echo ""
    log_info "Starting destruction process..."

    # Destruction steps
    pre_destruction_cleanup
    terraform_plan_destroy
    terraform_destroy
    verify_destruction
    show_destruction_summary

    echo ""
    log_success "AWS EKS Landing Zone destruction completed!"
}

# Function to show usage
show_usage() {
    echo "AWS EKS Landing Zone - Terraform Destruction Script"
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
trap 'log_error "Destruction interrupted"; exit 1' INT TERM

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