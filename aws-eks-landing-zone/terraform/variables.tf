# Environment and naming variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-cluster"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# VPC configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnet CIDRs are required for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnet CIDRs are required for high availability."
  }
}

variable "endpoints_subnet_cidrs" {
  description = "CIDR blocks for VPC endpoints subnets"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# EKS configuration
variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.(2[89]|3[0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.28 or higher."
  }
}

variable "enable_private_endpoint" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "enable_public_endpoint" {
  description = "Enable public API server endpoint (for management)"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Node groups configuration
variable "system_node_instance_types" {
  description = "Instance types for system node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_node_min_size" {
  description = "Minimum number of nodes in system node group"
  type        = number
  default     = 1

  validation {
    condition     = var.system_node_min_size >= 1 && var.system_node_min_size <= 10
    error_message = "System node min size must be between 1 and 10."
  }
}

variable "system_node_max_size" {
  description = "Maximum number of nodes in system node group"
  type        = number
  default     = 3

  validation {
    condition     = var.system_node_max_size >= 1 && var.system_node_max_size <= 20
    error_message = "System node max size must be between 1 and 20."
  }
}

variable "system_node_desired_size" {
  description = "Desired number of nodes in system node group"
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_desired_size >= 1
    error_message = "System node desired size must be at least 1."
  }
}

variable "user_node_instance_types" {
  description = "Instance types for user node group"
  type        = list(string)
  default     = ["m5.large"]
}

variable "user_node_min_size" {
  description = "Minimum number of nodes in user node group"
  type        = number
  default     = 2

  validation {
    condition     = var.user_node_min_size >= 1 && var.user_node_min_size <= 10
    error_message = "User node min size must be between 1 and 10."
  }
}

variable "user_node_max_size" {
  description = "Maximum number of nodes in user node group"
  type        = number
  default     = 10

  validation {
    condition     = var.user_node_max_size >= 1 && var.user_node_max_size <= 50
    error_message = "User node max size must be between 1 and 50."
  }
}

variable "user_node_desired_size" {
  description = "Desired number of nodes in user node group"
  type        = number
  default     = 3

  validation {
    condition     = var.user_node_desired_size >= 1
    error_message = "User node desired size must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 100

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 1000
    error_message = "Node disk size must be between 20 and 1000 GB."
  }
}

# ECR configuration
variable "enable_image_scanning" {
  description = "Enable ECR image vulnerability scanning"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "lifecycle_policy_days" {
  description = "Number of days to retain untagged images"
  type        = number
  default     = 7

  validation {
    condition     = var.lifecycle_policy_days >= 1 && var.lifecycle_policy_days <= 365
    error_message = "Lifecycle policy days must be between 1 and 365."
  }
}

# Monitoring configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

# Add-ons configuration
variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_driver" {
  description = "Enable Amazon EBS CSI Driver"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Enable Amazon EFS CSI Driver"
  type        = bool
  default     = false
}

# Security configuration
variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "vpc_flow_logs_retention" {
  description = "VPC Flow Logs retention in days"
  type        = number
  default     = 30
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for resources"
  type        = bool
  default     = true
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}