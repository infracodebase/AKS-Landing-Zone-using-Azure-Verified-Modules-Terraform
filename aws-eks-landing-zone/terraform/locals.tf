# Local values for consistent naming and configuration
locals {
  # Naming convention
  name_prefix  = "${var.cluster_name}-${var.environment}"
  cluster_name = "${var.cluster_name}-${var.environment}"

  # Availability zones (use first 2-3 available zones)
  azs = slice(data.aws_availability_zones.available.names, 0, min(length(var.private_subnet_cidrs), 3))

  # Common tags applied to all resources
  common_tags = merge(
    {
      Name         = local.name_prefix
      Environment  = var.environment
      Cluster      = local.cluster_name
      ManagedBy    = "Terraform"
      Project      = "EKS-Landing-Zone"
      Owner        = data.aws_caller_identity.current.arn
      CreatedBy    = "terraform"
      Region       = var.aws_region
      CostCenter   = "Infrastructure"
      Backup       = var.environment == "prod" ? "required" : "optional"
      Monitoring   = "enabled"
      Compliance   = "aws-security-baseline"
    },
    var.additional_tags
  )

  # EKS cluster configuration
  cluster_config = {
    cluster_version                 = var.kubernetes_version
    cluster_endpoint_private_access = var.enable_private_endpoint
    cluster_endpoint_public_access  = var.enable_public_endpoint
    cluster_endpoint_public_access_cidrs = var.public_access_cidrs

    # Enable all control plane logging
    cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

    # Cluster encryption configuration
    cluster_encryption_config = var.enable_kms_encryption ? [
      {
        provider_key_arn = aws_kms_key.eks_secrets[0].arn
        resources        = ["secrets"]
      }
    ] : []
  }

  # Node group configurations
  system_node_group = {
    name           = "${local.name_prefix}-system"
    instance_types = var.system_node_instance_types
    min_size       = var.system_node_min_size
    max_size       = var.system_node_max_size
    desired_size   = var.system_node_desired_size

    # System workloads taint
    taints = [
      {
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]

    labels = {
      "nodegroup-type"              = "system"
      "node.kubernetes.io/purpose"  = "system"
    }
  }

  user_node_group = {
    name           = "${local.name_prefix}-user"
    instance_types = var.user_node_instance_types
    min_size       = var.user_node_min_size
    max_size       = var.user_node_max_size
    desired_size   = var.user_node_desired_size

    labels = {
      "nodegroup-type"              = "user"
      "node.kubernetes.io/purpose"  = "application"
    }
  }

  # EKS add-ons configuration
  cluster_addons = {
    coredns = {
      addon_version = "latest"
      configuration_values = jsonencode({
        replicaCount = 2
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      })
    }

    kube-proxy = {
      addon_version = "latest"
    }

    vpc-cni = {
      addon_version = "latest"
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI           = "true"
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
      })
    }

    aws-ebs-csi-driver = var.enable_ebs_csi_driver ? {
      addon_version = "latest"
      service_account_role_arn = module.ebs_csi_driver_irsa_role.iam_role_arn
    } : null

    aws-efs-csi-driver = var.enable_efs_csi_driver ? {
      addon_version = "latest"
      service_account_role_arn = module.efs_csi_driver_irsa_role[0].iam_role_arn
    } : null

    amazon-cloudwatch-observability = var.enable_container_insights ? {
      addon_version = "latest"
      service_account_role_arn = module.cloudwatch_observability_irsa_role.iam_role_arn
    } : null
  }

  # VPC Endpoints for private connectivity
  vpc_endpoints = {
    s3 = {
      service_name    = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }

    ecr_api = {
      service_name        = "ecr.api"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    ecr_dkr = {
      service_name        = "ecr.dkr"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    eks = {
      service_name        = "eks"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    secretsmanager = {
      service_name        = "secretsmanager"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    ssm = {
      service_name        = "ssm"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    logs = {
      service_name        = "logs"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    monitoring = {
      service_name        = "monitoring"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    sts = {
      service_name        = "sts"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    ec2 = {
      service_name        = "ec2"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }

    autoscaling = {
      service_name        = "autoscaling"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
    }
  }

  # ECR repository names
  ecr_repositories = [
    {
      name                 = local.name_prefix
      image_tag_mutability = var.image_tag_mutability
      scan_on_push        = var.enable_image_scanning
    },
    {
      name                 = "${local.name_prefix}-base"
      image_tag_mutability = "IMMUTABLE"
      scan_on_push        = true
    }
  ]

  # ECR lifecycle policy
  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.lifecycle_policy_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_policy_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}