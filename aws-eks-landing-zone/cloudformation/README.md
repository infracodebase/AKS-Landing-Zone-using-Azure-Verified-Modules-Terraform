# AWS EKS Landing Zone - CloudFormation Implementation

This directory contains CloudFormation templates for deploying a production-ready, secure AWS EKS landing zone using AWS native infrastructure as code.

## Architecture Overview

### Infrastructure Components

```
┌─ Internet (External Traffic)
│
├─ VPC (10.0.0.0/16)
│  │
│  ├─ Public Subnets (10.0.10.0/24, 10.0.11.0/24)
│  │  ├─ NAT Gateways
│  │  └─ Internet Gateway
│  │
│  ├─ Private Subnets (10.0.1.0/24, 10.0.2.0/24)
│  │  ├─ EKS Cluster (Private API)
│  │  ├─ System Node Pool (t3.medium, 1-3 nodes)
│  │  └─ User Node Pool (m5.large, 2-10 nodes, autoscaling)
│  │
│  └─ VPC Endpoints Subnets (10.0.20.0/24, 10.0.21.0/24)
│     ├─ ECR API/DKR Endpoints
│     ├─ S3 Gateway Endpoint
│     ├─ Secrets Manager Endpoint
│     ├─ CloudWatch Logs Endpoint
│     └─ EKS API Endpoint
│
├─ ECR Repositories (KMS Encrypted)
│  ├─ Application Repository
│  └─ Base Images Repository
│
├─ Secrets Management
│  ├─ AWS Secrets Manager (KMS Encrypted)
│  ├─ SSM Parameter Store
│  └─ KMS Keys for Encryption
│
├─ Monitoring & Logging
│  ├─ CloudWatch Log Groups
│  ├─ Container Insights
│  └─ S3 Bucket for Artifacts
│
└─ IAM Roles & IRSA
   ├─ EKS Cluster Service Role
   ├─ EKS Node Instance Role
   ├─ Load Balancer Controller Role (IRSA)
   ├─ EBS CSI Driver Role (IRSA)
   ├─ Cluster Autoscaler Role (IRSA)
   └─ CloudWatch Container Insights Role (IRSA)
```

### Security Features

#### Network Security
- **Private-by-Default**: EKS API server accessible only via private endpoint
- **VPC Endpoints**: All AWS service communication via private endpoints
- **Security Groups**: Least-privilege access rules
- **Network Segmentation**: Separate subnets for compute, endpoints, and public resources

#### Identity & Access Management
- **IAM Roles for Service Accounts (IRSA)**: No static credentials
- **OIDC Identity Provider**: Secure workload identity federation
- **Least Privilege**: Minimal required permissions for each component
- **Service-Linked Roles**: AWS-managed roles where possible

#### Data Protection
- **Encryption at Rest**: KMS encryption for ECR, Secrets Manager, EBS volumes
- **Encryption in Transit**: TLS 1.2+ for all communications
- **Secrets Management**: Centralized secret storage with rotation support
- **Container Image Security**: Vulnerability scanning enabled

#### Monitoring & Compliance
- **CloudWatch Integration**: Container insights and custom metrics
- **Audit Logging**: All EKS API calls logged to CloudWatch
- **Resource Tagging**: Consistent tagging for cost allocation and governance

## Template Structure

### 01-vpc-network.yaml
**Purpose**: Core networking infrastructure
- VPC with DNS support
- Public/private subnets across 2 AZs
- NAT Gateways for outbound internet access
- Security groups for EKS cluster and nodes
- Route tables and internet gateway

**Outputs**: VPC ID, subnet IDs, security group IDs

### 02-vpc-endpoints.yaml
**Purpose**: Private AWS service connectivity
- Interface endpoints: ECR, EKS, Secrets Manager, CloudWatch, STS
- Gateway endpoint: S3
- Private DNS resolution
- Endpoint-specific IAM policies

**Dependencies**: VPC stack
**Outputs**: Endpoint IDs, private hosted zone

### 03-iam-roles.yaml
**Purpose**: IAM roles and policies
- EKS cluster service role
- Node instance roles with enhanced permissions
- IRSA roles for workload identity (conditional on OIDC issuer)
- Service-specific policies (ALB controller, CSI driver, autoscaler)

**Conditional Resources**: IRSA roles created only after OIDC provider setup
**Outputs**: Role ARNs for use by other stacks

### 04-ecr-secrets.yaml
**Purpose**: Container registry and secrets management
- ECR repositories with lifecycle policies
- KMS keys for encryption
- Secrets Manager secrets with rotation
- CloudWatch log groups
- S3 bucket for cluster artifacts

**Dependencies**: VPC stack (for S3 bucket naming)
**Outputs**: Repository URIs, secret ARNs, resource IDs

### 05-eks-cluster.yaml
**Purpose**: EKS cluster and node groups
- EKS cluster with private API endpoint
- System node group (tainted for system workloads)
- User node group (for application workloads)
- EKS add-ons (CoreDNS, VPC CNI, EBS CSI, CloudWatch)
- Launch templates with optimized configurations

**Dependencies**: All previous stacks
**Outputs**: Cluster details, OIDC issuer URL, node group names

## Deployment Guide

### Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Administrative access** to the target AWS account
3. **Region selection** - verify EKS availability in your chosen region

### Required IAM Permissions

The deploying user/role needs these permissions:
- CloudFormation: Full access
- IAM: Create/modify roles, policies, instance profiles
- EC2: Full VPC and instance management
- EKS: Full cluster management
- ECR: Repository management
- Secrets Manager: Secret management
- S3: Bucket management
- CloudWatch: Log group management
- KMS: Key management

### Quick Deployment

```bash
# Clone and navigate to the project
cd aws-eks-landing-zone

# Deploy with defaults (dev environment)
./scripts/deploy-cloudformation.sh

# Deploy production environment
./scripts/deploy-cloudformation.sh -e prod -c production-eks -r us-west-2
```

### Custom Parameters

```bash
# Set environment variables
export ENVIRONMENT_NAME=staging
export CLUSTER_NAME=acme-eks
export AWS_REGION=eu-west-1

# Deploy with custom settings
./scripts/deploy-cloudformation.sh
```

### Step-by-Step Deployment

```bash
# 1. Validate templates
aws cloudformation validate-template --template-body file://01-vpc-network.yaml

# 2. Deploy VPC (15-20 minutes)
aws cloudformation deploy \
  --template-file 01-vpc-network.yaml \
  --stack-name acme-eks-dev-vpc \
  --parameter-overrides \
    EnvironmentName=dev \
    ClusterName=acme-eks

# 3. Deploy VPC Endpoints (5-10 minutes)
aws cloudformation deploy \
  --template-file 02-vpc-endpoints.yaml \
  --stack-name acme-eks-dev-endpoints \
  --parameter-overrides \
    VPCStackName=acme-eks-dev-vpc \
    EnvironmentName=dev \
    ClusterName=acme-eks

# 4. Deploy IAM Roles (2-5 minutes)
aws cloudformation deploy \
  --template-file 03-iam-roles.yaml \
  --stack-name acme-eks-dev-iam \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    EnvironmentName=dev \
    ClusterName=acme-eks

# 5. Deploy ECR and Secrets (5-10 minutes)
aws cloudformation deploy \
  --template-file 04-ecr-secrets.yaml \
  --stack-name acme-eks-dev-ecr \
  --parameter-overrides \
    VPCStackName=acme-eks-dev-vpc \
    EnvironmentName=dev \
    ClusterName=acme-eks

# 6. Deploy EKS Cluster (20-30 minutes)
aws cloudformation deploy \
  --template-file 05-eks-cluster.yaml \
  --stack-name acme-eks-dev-eks \
  --parameter-overrides \
    VPCStackName=acme-eks-dev-vpc \
    IAMStackName=acme-eks-dev-iam \
    ECRStackName=acme-eks-dev-ecr \
    EndpointsStackName=acme-eks-dev-endpoints \
    EnvironmentName=dev \
    ClusterName=acme-eks

# 7. Set up OIDC Provider and update IAM (manual step)
# Get OIDC issuer URL from EKS cluster
OIDC_ISSUER=$(aws eks describe-cluster --name acme-eks-dev --query "cluster.identity.oidc.issuer" --output text)
OIDC_HOST=$(echo $OIDC_ISSUER | sed 's/https:\/\///')

# Update IAM stack with OIDC issuer
aws cloudformation deploy \
  --template-file 03-iam-roles.yaml \
  --stack-name acme-eks-dev-iam \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    EnvironmentName=dev \
    ClusterName=acme-eks \
    EKSOIDCIssuerURL=$OIDC_HOST
```

### Post-Deployment Configuration

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name acme-eks-dev

# Verify cluster access
kubectl get nodes
kubectl get pods -A

# Install additional components (optional)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENVIRONMENT_NAME` | `dev` | Environment (dev, staging, prod) |
| `CLUSTER_NAME` | `eks-cluster` | EKS cluster name |
| `AWS_REGION` | `us-east-1` | AWS region |
| `STACK_PREFIX` | `${CLUSTER_NAME}-${ENVIRONMENT_NAME}` | CloudFormation stack prefix |

### Template Parameters

#### VPC Configuration
- `VpcCidr`: VPC CIDR block (default: 10.0.0.0/16)
- `PrivateSubnet1Cidr`: Private subnet 1 CIDR (default: 10.0.1.0/24)
- `PrivateSubnet2Cidr`: Private subnet 2 CIDR (default: 10.0.2.0/24)
- `PublicSubnet1Cidr`: Public subnet 1 CIDR (default: 10.0.10.0/24)
- `PublicSubnet2Cidr`: Public subnet 2 CIDR (default: 10.0.11.0/24)

#### EKS Configuration
- `KubernetesVersion`: Kubernetes version (default: 1.31)
- `SystemNodeInstanceType`: System node instance type (default: t3.medium)
- `UserNodeInstanceType`: User node instance type (default: m5.large)
- `SystemNodeMinSize/MaxSize`: System node group scaling (default: 1-3)
- `UserNodeMinSize/MaxSize`: User node group scaling (default: 2-10)
- `EnablePrivateEndpoint`: Enable private API endpoint (default: true)
- `EnablePublicEndpoint`: Enable public API endpoint (default: false)

#### ECR Configuration
- `EnableImageScanning`: Enable vulnerability scanning (default: true)
- `ImageTagMutability`: Tag mutability (default: MUTABLE)
- `LifecyclePolicyDays`: Days to retain untagged images (default: 7)

## Cost Optimization

### Instance Sizing Recommendations

| Environment | System Nodes | User Nodes | Estimated Monthly Cost* |
|-------------|--------------|------------|------------------------|
| **Development** | 1x t3.small | 2x t3.medium | $150-200 |
| **Staging** | 2x t3.medium | 3x m5.large | $400-500 |
| **Production** | 3x t3.large | 5x m5.xlarge | $800-1200 |

*Estimates include compute, storage, and data transfer. Excludes NAT Gateway costs (~$45/month per gateway).

### Cost Optimization Features

- **Auto Scaling**: Nodes scale down to minimum when not needed
- **Spot Instances**: Can be enabled for non-critical workloads
- **EBS GP3 Volumes**: Cost-effective storage with performance tuning
- **VPC Endpoints**: Reduce NAT Gateway data transfer costs
- **ECR Lifecycle Policies**: Automatic image cleanup

## Security Considerations

### Network Security Baseline

```bash
# Verify private cluster access
kubectl get nodes --server=https://PRIVATE-ENDPOINT

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]'

# Verify VPC endpoint connectivity
nslookup ecr.REGION.amazonaws.com
```

### Compliance Frameworks

This implementation aligns with:

- **AWS Well-Architected Framework**: All 6 pillars
- **CIS Kubernetes Benchmark**: Security controls
- **NIST Cybersecurity Framework**: Comprehensive coverage
- **SOC 2 Type II**: Security and availability
- **ISO 27001**: Information security management
- **PCI DSS Level 1**: Payment card security (with additional controls)

### Security Scanning

```bash
# Validate security posture with AWS Security Hub
aws securityhub get-findings \
  --filters ProductArn=[{Value="arn:aws:securityhub:*:*:product/*/EKS"}]

# ECR image vulnerability scanning
aws ecr describe-image-scan-findings \
  --repository-name acme-eks-dev \
  --image-id imageTag=latest
```

## Troubleshooting

### Common Issues

#### 1. Stack Creation Failures

```bash
# Check stack events for errors
aws cloudformation describe-stack-events --stack-name STACK_NAME

# View failed resources
aws cloudformation list-stack-resources \
  --stack-name STACK_NAME \
  --stack-resource-status DELETE_FAILED
```

#### 2. EKS Cluster Access Issues

```bash
# Verify IAM permissions
aws sts get-caller-identity

# Check cluster status
aws eks describe-cluster --name CLUSTER_NAME

# Update kubeconfig
aws eks update-kubeconfig --region REGION --name CLUSTER_NAME
```

#### 3. Node Group Issues

```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name CLUSTER_NAME \
  --nodegroup-name NODEGROUP_NAME

# View Auto Scaling Group details
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names NODEGROUP_ASG_NAME
```

#### 4. VPC Endpoint Connectivity

```bash
# Test endpoint connectivity from within VPC
dig +short ecr.api.REGION.amazonaws.com

# Check endpoint policy
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids ENDPOINT_ID
```

### Recovery Procedures

#### Partial Failure Recovery

```bash
# Continue deployment from failed stack
aws cloudformation continue-update-rollback --stack-name STACK_NAME

# Update stack with corrected template
aws cloudformation deploy \
  --template-file TEMPLATE.yaml \
  --stack-name STACK_NAME \
  --capabilities CAPABILITY_NAMED_IAM
```

#### Complete Environment Recreation

```bash
# Safe destruction (preserves data)
./scripts/destroy-cloudformation.sh -e ENVIRONMENT -c CLUSTER_NAME

# Redeploy from scratch
./scripts/deploy-cloudformation.sh -e ENVIRONMENT -c CLUSTER_NAME
```

## Monitoring and Operations

### CloudWatch Dashboards

Post-deployment, create dashboards for:
- Cluster resource utilization
- Node group scaling metrics
- Application performance metrics
- Security and compliance metrics

### Log Analysis

```bash
# View cluster logs
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/CLUSTER_NAME"

# Application logs
kubectl logs -f deployment/APP_NAME -c CONTAINER_NAME
```

### Backup Strategy

- **EKS Configuration**: Infrastructure as Code (CloudFormation)
- **Application Data**: Velero for Kubernetes backup
- **Container Images**: ECR with cross-region replication
- **Secrets**: AWS Backup for Secrets Manager

## Support and Maintenance

### Regular Maintenance Tasks

1. **Monthly**: Update EKS add-ons and node groups
2. **Quarterly**: Review and update Kubernetes version
3. **Bi-annually**: Security review and penetration testing
4. **Annually**: Disaster recovery testing

### Upgrade Procedures

```bash
# Update EKS cluster version
aws eks update-cluster-version \
  --name CLUSTER_NAME \
  --kubernetes-version 1.31

# Update node groups
aws eks update-nodegroup-version \
  --cluster-name CLUSTER_NAME \
  --nodegroup-name NODEGROUP_NAME
```

This CloudFormation implementation provides a solid foundation for production EKS workloads with enterprise-grade security, monitoring, and operational capabilities.