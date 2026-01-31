# Cluster outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks_cluster.eks_cluster_id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks_cluster.eks_cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks_cluster.eks_cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the EKS cluster"
  value       = module.eks_cluster.eks_cluster_version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = module.eks_cluster.eks_cluster_version
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of `CREATING`, `ACTIVE`, `DELETING`, `FAILED`"
  value       = module.eks_cluster.eks_cluster_arn != "" ? "ACTIVE" : "UNKNOWN"
}

# OIDC Provider outputs
output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks_cluster.eks_cluster_identity_oidc_issuer
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if enabled"
  value       = module.eks_cluster.eks_cluster_identity_oidc_issuer_arn
}

# Security outputs
output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS node groups"
  value       = aws_security_group.eks_nodes.id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.eks_cluster_certificate_authority_data
  sensitive   = true
}

# IAM outputs
output "cluster_service_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = module.eks_cluster.eks_cluster_role_arn
}

output "node_instance_role_arn" {
  description = "ARN of the EKS node instance role"
  value       = aws_iam_role.eks_node_group.arn
}

output "node_instance_profile_name" {
  description = "Name of the EKS node instance profile"
  value       = aws_iam_instance_profile.eks_node_group.name
}

# IRSA Role ARNs
output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI Driver IRSA role"
  value       = module.ebs_csi_driver_irsa_role.iam_role_arn
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role"
  value       = var.enable_aws_load_balancer_controller ? module.load_balancer_controller_irsa_role[0].iam_role_arn : null
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_irsa_role[0].iam_role_arn : null
}

output "cloudwatch_observability_role_arn" {
  description = "ARN of the CloudWatch Container Insights IRSA role"
  value       = module.cloudwatch_observability_irsa_role.iam_role_arn
}

# Node Group outputs
output "system_node_group_arn" {
  description = "Amazon Resource Name (ARN) of the EKS System Node Group"
  value       = aws_eks_node_group.system.arn
}

output "system_node_group_status" {
  description = "Status of the EKS System Node Group"
  value       = aws_eks_node_group.system.status
}

output "user_node_group_arn" {
  description = "Amazon Resource Name (ARN) of the EKS User Node Group"
  value       = aws_eks_node_group.user.arn
}

output "user_node_group_status" {
  description = "Status of the EKS User Node Group"
  value       = aws_eks_node_group.user.status
}

# VPC outputs
output "vpc_id" {
  description = "ID of the VPC where the cluster and nodes are deployed"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "nat_gateway_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = module.vpc.natgw_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.igw_id
}

# ECR outputs
output "ecr_repository_urls" {
  description = "Map of ECR repository URLs"
  value       = { for k, v in aws_ecr_repository.repositories : k => v.repository_url }
}

output "ecr_registry_id" {
  description = "Registry ID where the repositories are created"
  value       = values(aws_ecr_repository.repositories)[0].registry_id
}

# Secrets Manager outputs
output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.database_credentials.arn
}

output "api_keys_secret_arn" {
  description = "ARN of the API keys secret"
  value       = aws_secretsmanager_secret.api_keys.arn
}

output "tls_certificates_secret_arn" {
  description = "ARN of the TLS certificates secret"
  value       = aws_secretsmanager_secret.tls_certificates.arn
}

# KMS Key outputs
output "eks_kms_key_id" {
  description = "KMS key ID for EKS cluster encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.eks_secrets[0].key_id : null
}

output "ecr_kms_key_id" {
  description = "KMS key ID for ECR encryption"
  value       = aws_kms_key.ecr.key_id
}

output "secrets_manager_kms_key_id" {
  description = "KMS key ID for Secrets Manager encryption"
  value       = aws_kms_key.secrets_manager.key_id
}

output "cloudwatch_kms_key_id" {
  description = "KMS key ID for CloudWatch logs encryption"
  value       = aws_kms_key.cloudwatch.key_id
}

# CloudWatch outputs
output "cluster_log_group_name" {
  description = "Name of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.cluster.name
}

output "container_log_group_name" {
  description = "Name of the CloudWatch log group for container logs"
  value       = aws_cloudwatch_log_group.containers.name
}

output "application_log_group_name" {
  description = "Name of the CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.applications.name
}

# S3 outputs
output "cluster_artifacts_bucket_name" {
  description = "Name of the S3 bucket for cluster artifacts"
  value       = aws_s3_bucket.cluster_artifacts.bucket
}

output "cluster_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for cluster artifacts"
  value       = aws_s3_bucket.cluster_artifacts.arn
}

# Monitoring outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.eks_cluster.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

# Configuration outputs
output "kubectl_config" {
  description = "kubectl config as generated by the module"
  value = {
    cluster_name             = local.cluster_name
    endpoint                = module.eks_cluster.eks_cluster_endpoint
    certificate_authority   = module.eks_cluster.eks_cluster_certificate_authority_data
    region                  = data.aws_region.current.name
    role_arn               = module.eks_cluster.eks_cluster_role_arn
  }
  sensitive = true
}

output "kubeconfig_update_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${local.cluster_name}"
}

# Add-ons outputs
output "eks_addons" {
  description = "Map of enabled EKS addons"
  value       = module.eks_cluster.eks_addons_versions
}

# Summary output
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    cluster = {
      name     = local.cluster_name
      version  = var.kubernetes_version
      endpoint = module.eks_cluster.eks_cluster_endpoint
      region   = data.aws_region.current.name
    }
    networking = {
      vpc_id             = module.vpc.vpc_id
      vpc_cidr          = module.vpc.vpc_cidr_block
      private_subnets   = length(module.vpc.private_subnets)
      public_subnets    = length(module.vpc.public_subnets)
      nat_gateways      = length(module.vpc.natgw_ids)
    }
    compute = {
      system_nodes = {
        instance_types = var.system_node_instance_types
        min_size      = var.system_node_min_size
        max_size      = var.system_node_max_size
        desired_size  = var.system_node_desired_size
      }
      user_nodes = {
        instance_types = var.user_node_instance_types
        min_size      = var.user_node_min_size
        max_size      = var.user_node_max_size
        desired_size  = var.user_node_desired_size
      }
    }
    storage = {
      ecr_repositories = length(aws_ecr_repository.repositories)
      secrets_count    = 3 # database, api_keys, tls_certificates
      s3_bucket       = aws_s3_bucket.cluster_artifacts.bucket
    }
    security = {
      kms_encryption_enabled = var.enable_kms_encryption
      vpc_flow_logs_enabled  = var.enable_vpc_flow_logs
      private_endpoint       = var.enable_private_endpoint
      public_endpoint        = var.enable_public_endpoint
    }
    monitoring = {
      container_insights_enabled = var.enable_container_insights
      log_retention_days         = var.log_retention_days
      cloudwatch_dashboard       = aws_cloudwatch_dashboard.eks_cluster.dashboard_name
    }
  }
}