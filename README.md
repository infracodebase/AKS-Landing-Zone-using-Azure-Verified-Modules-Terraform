# AWS EKS Landing Zone - Production Ready

This repository contains a production-ready, secure AWS Elastic Kubernetes Service (EKS) landing zone implementation following AWS security best practices, the AWS Well-Architected Framework, and enterprise security standards.

## Architecture Overview

This deployment creates a comprehensive AWS Landing Zone with:
- **Private EKS cluster** with no public endpoint
- **Virtual Private Cloud (VPC)** with dedicated subnets and security boundaries
- **Elastic Container Registry (ECR)** with KMS encryption
- **AWS Secrets Manager** for secrets management
- **CloudWatch** for monitoring and observability
- **VPC Endpoints** for private AWS service connectivity
- **IAM Roles for Service Accounts (IRSA)** for secure workload identity

## Project Structure

```
aws-eks-landing-zone/
├── cloudformation/              # CloudFormation Implementation
│   ├── 01-vpc-network.yaml     # VPC, subnets, security groups
│   ├── 02-vpc-endpoints.yaml   # Private endpoints for AWS services
│   ├── 03-iam-roles.yaml       # IAM roles and IRSA configuration
│   ├── 04-ecr-secrets.yaml     # ECR repositories and secrets
│   ├── 05-eks-cluster.yaml     # EKS cluster and node groups
│   └── README.md               # CloudFormation deployment guide
│
├── terraform/                   # Terraform Implementation
│   ├── *.tf files              # Complete Terraform configuration
│   ├── templates/              # Launch templates and scripts
│   └── scripts/                # Deployment automation
│
├── scripts/                     # Deployment Scripts
│   ├── deploy-cloudformation.sh # CloudFormation automation
│   └── destroy-cloudformation.sh # Safe destruction script
│
├── security-docs/               # Security Documentation
│   ├── SECURITY_DOCUMENTATION.md # Complete security reference
│   └── SECURITY_REPORT.md       # Executive security summary
│
├── .infracodebase/             # Architecture Diagrams
│   └── aws-eks-clean-architecture.json # Visual architecture
│
├── README.md                   # This file - complete project overview
├── DEPLOYMENT_SUMMARY.md       # Implementation summary
└── PROJECT_STRUCTURE.md        # Detailed organization guide
```

## Security Features

- **Private cluster** - No public API server endpoint
- **Network policies** - VPC CNI with security groups
- **IRSA (IAM Roles for Service Accounts)** - Passwordless authentication
- **Private Container Registry** - ECR with KMS encryption
- **VPC Endpoints** - Private connectivity to AWS services
- **Secrets management** - AWS Secrets Manager integration
- **Network isolation** - Dedicated subnets and security groups
- **CloudWatch monitoring** - Comprehensive observability

## Quick Start

### Option 1: CloudFormation Deployment (Recommended)
```bash
# Navigate to project directory
cd aws-eks-landing-zone/

# Deploy using automation script
./scripts/deploy-cloudformation.sh

# Or deploy with custom parameters
./scripts/deploy-cloudformation.sh -e prod -c my-eks -r us-west-2
```

### Option 2: Terraform Deployment
```bash
# Navigate to terraform directory
cd aws-eks-landing-zone/terraform/

# Deploy using automation script
./scripts/deploy.sh

# OR deploy manually
terraform init
terraform plan
terraform apply
```

### Access Your Cluster
```bash
# Get cluster credentials (requires VPC connectivity)
aws eks update-kubeconfig --region us-east-1 --name eks-cluster-dev

# Verify connection
kubectl get nodes

# Test cluster functionality
kubectl get services -A
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured (`aws configure` or IAM roles)
3. **kubectl** installed for cluster management
4. **Terraform** >= 1.9.0 (for Terraform deployment)
5. **Network connectivity** to private cluster (VPN, bastion, or VPC)

### Required AWS Permissions:
- CloudFormation: Full access
- IAM: Create/modify roles, policies, instance profiles
- EC2: Full VPC and instance management
- EKS: Full cluster management
- ECR: Repository management
- Secrets Manager: Secret management
- S3: Bucket management
- CloudWatch: Log group management
- KMS: Key management

## Technology Stack

### Infrastructure as Code:
- **CloudFormation** - AWS native IaC with 5 modular templates
- **Terraform** >= 1.9.0 with AWS Provider >= 5.75.1
- **Community Modules** - terraform-aws-modules for best practices

### AWS Services:
- **Amazon EKS** (Private cluster with managed node groups)
- **Amazon ECR** (Private registry with vulnerability scanning)
- **AWS Secrets Manager** (KMS encrypted secrets)
- **Amazon VPC** (Multi-AZ with private/public subnets)
- **CloudWatch** (Container insights and monitoring)
- **VPC Endpoints** (Private connectivity to AWS services)

## Security & Compliance

### Security Features:
- **Zero Trust Networking** - Private cluster with VPC endpoints
- **Encryption at Rest** - KMS encryption for all data
- **Encryption in Transit** - TLS 1.2+ for all communications
- **Identity & Access Management** - IRSA for workload identity
- **Network Segmentation** - Dedicated subnets and security groups

### Compliance Frameworks:
- **AWS Security Benchmark** COMPLIANT
- **CIS Kubernetes Benchmark** COMPLIANT
- **NIST Cybersecurity Framework** ALIGNED

### Regulatory Readiness:
- **SOC 2 Type II** Ready
- **ISO 27001** Ready
- **PCI DSS** Ready (with additional controls)
- **HIPAA** Ready (with additional controls)
- **GDPR** Ready

## Architecture Patterns

### AWS Landing Zone Design:
- **Network Segmentation** - Separate subnets for compute, endpoints, public resources
- **Private Connectivity** - All AWS services via VPC endpoints
- **Zero Trust Networking** - Security groups with least privilege
- **Identity Integration** - IAM roles and OIDC for workload identity

### Kubernetes Security:
- **Private API Server** - No public internet access
- **Security Groups** - Pod-level security controls
- **Workload Identity** - IRSA for seamless AWS service integration
- **Image Security** - ECR vulnerability scanning and lifecycle policies

## Deployment Options

### CloudFormation (Recommended):
```bash
# Automated deployment with validation
./scripts/deploy-cloudformation.sh

# Custom environment deployment
./scripts/deploy-cloudformation.sh -e prod -c acme-eks -r us-west-2
```

### Terraform:
```bash
cd terraform/
./scripts/deploy.sh  # Includes validation, planning, and deployment
```

### Manual CloudFormation:
```bash
# Deploy step by step
aws cloudformation deploy --template-file 01-vpc-network.yaml --stack-name eks-vpc
aws cloudformation deploy --template-file 02-vpc-endpoints.yaml --stack-name eks-endpoints
# ... continue with remaining templates
```

## Cost Optimization

- **Auto-scaling enabled** - Nodes scale based on demand
- **Managed node groups** - AWS managed infrastructure
- **VPC endpoints** - Reduce NAT gateway costs
- **ECR lifecycle policies** - Automatic image cleanup
- **CloudWatch log retention** - Configurable retention periods

## Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| **cloudformation/README.md** | Complete CloudFormation guide | DevOps, Platform teams |
| **security-docs/SECURITY_DOCUMENTATION.md** | Security reference | Security, Compliance teams |
| **security-docs/SECURITY_REPORT.md** | Executive security summary | Management, Auditors |
| **DEPLOYMENT_SUMMARY.md** | Implementation overview | All stakeholders |
| **PROJECT_STRUCTURE.md** | Project organization | New team members |

## Monitoring & Operations

### CloudWatch Integration:
- **Container Insights** - Real-time metrics and logs
- **Custom Metrics** - Application and infrastructure monitoring
- **Log Aggregation** - Centralized logging with retention policies
- **Alerting** - CloudWatch Alarms for critical events

### Operational Features:
- **Auto Scaling** - Horizontal and vertical pod autoscaling
- **Managed Updates** - AWS managed control plane updates
- **Backup Strategy** - Automated backups for persistent volumes
- **Disaster Recovery** - Multi-AZ deployment for high availability

## Support & Contributing

### Getting Help:
- Review [Amazon EKS documentation](https://docs.aws.amazon.com/eks/)
- Check [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- Review security documentation in security-docs/
- Open GitHub issues for bugs or questions

### Contributing:
1. Fork the repository
2. Create feature branch
3. Follow established coding standards
4. Update documentation
5. Submit pull request with security review

---

**This repository provides an enterprise-grade, security-first Amazon EKS landing zone that's ready for production deployment with comprehensive CloudFormation and Terraform implementations, automated security validation, and full compliance framework alignment.**