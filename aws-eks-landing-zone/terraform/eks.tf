# EKS Cluster using CloudPosse module
module "eks_cluster" {
  source  = "cloudposse/eks-cluster/aws"
  version = "~> 4.0"

  namespace   = "eks"
  stage       = var.environment
  name        = var.cluster_name
  attributes  = ["cluster"]

  region     = var.aws_region
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster configuration
  kubernetes_version                   = var.kubernetes_version
  endpoint_private_access              = var.enable_private_endpoint
  endpoint_public_access               = var.enable_public_endpoint
  public_access_cidrs                 = var.public_access_cidrs
  cluster_encryption_config_enabled   = var.enable_kms_encryption
  cluster_encryption_config_kms_key_id = var.enable_kms_encryption ? aws_kms_key.eks_secrets[0].arn : null

  # Security groups
  associated_security_group_ids = [aws_security_group.eks_cluster.id]
  managed_security_group_rules_enabled = true

  # Logging configuration
  enabled_cluster_log_types = local.cluster_config.cluster_enabled_log_types
  cluster_log_retention_period = var.log_retention_days
  cloudwatch_log_group_kms_key_id = aws_kms_key.cloudwatch.arn

  # OIDC provider
  oidc_provider_enabled = true

  # Access configuration
  access_config = {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Add-ons configuration
  addons = [
    for addon_name, addon_config in local.cluster_addons : {
      addon_name                  = addon_name
      addon_version              = try(addon_config.addon_version, "latest")
      configuration_values       = try(addon_config.configuration_values, null)
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      service_account_role_arn   = try(addon_config.service_account_role_arn, null)
    } if addon_config != null
  ]

  tags = local.common_tags

  depends_on = [
    aws_security_group.eks_cluster,
    aws_security_group.eks_nodes
  ]
}

# EKS Node Groups
resource "aws_eks_node_group" "system" {
  cluster_name    = module.eks_cluster.eks_cluster_id
  node_group_name = local.system_node_group.name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets

  # AMI configuration
  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  instance_types = local.system_node_group.instance_types
  disk_size      = var.node_disk_size

  # Scaling configuration
  scaling_config {
    desired_size = local.system_node_group.desired_size
    max_size     = local.system_node_group.max_size
    min_size     = local.system_node_group.min_size
  }

  # Update configuration
  update_config {
    max_unavailable = 1
  }

  # Remote access configuration (disabled for security)
  # remote_access {
  #   ec2_ssh_key = var.key_pair_name
  # }

  # Launch template
  launch_template {
    id      = aws_launch_template.system_nodes.id
    version = aws_launch_template.system_nodes.latest_version
  }

  # Node group labels
  labels = local.system_node_group.labels

  # Taints for system workloads only
  dynamic "taint" {
    for_each = local.system_node_group.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.common_tags, {
    Name                                           = local.system_node_group.name
    Type                                           = "EKS-NodeGroup"
    "k8s.io/cluster-autoscaler/enabled"           = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  })

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_node_group" "user" {
  cluster_name    = module.eks_cluster.eks_cluster_id
  node_group_name = local.user_node_group.name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets

  # AMI configuration
  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  instance_types = local.user_node_group.instance_types
  disk_size      = var.node_disk_size

  # Scaling configuration
  scaling_config {
    desired_size = local.user_node_group.desired_size
    max_size     = local.user_node_group.max_size
    min_size     = local.user_node_group.min_size
  }

  # Update configuration
  update_config {
    max_unavailable_percentage = 25
  }

  # Launch template
  launch_template {
    id      = aws_launch_template.user_nodes.id
    version = aws_launch_template.user_nodes.latest_version
  }

  # Node group labels
  labels = local.user_node_group.labels

  tags = merge(local.common_tags, {
    Name                                           = local.user_node_group.name
    Type                                           = "EKS-NodeGroup"
    "k8s.io/cluster-autoscaler/enabled"           = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  })

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
    aws_eks_node_group.system, # System nodes must be ready first
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Launch Templates
resource "aws_launch_template" "system_nodes" {
  name_prefix   = "${local.name_prefix}-system-"
  description   = "Launch template for EKS system node group"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = local.system_node_group.instance_types[0]

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    cluster_name = local.cluster_name
    node_type    = "system"
  }))

  # EBS volume configuration
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      kms_key_id           = aws_kms_key.ecr.arn
      delete_on_termination = true
    }
  }

  # Instance metadata service configuration
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Network interface configuration
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups            = [aws_security_group.eks_nodes.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-system-node"
      Type = "EKS-SystemNode"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-system-node-volume"
      Type = "EBS-Volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-system-launch-template"
    Type = "LaunchTemplate"
  })
}

resource "aws_launch_template" "user_nodes" {
  name_prefix   = "${local.name_prefix}-user-"
  description   = "Launch template for EKS user node group"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = local.user_node_group.instance_types[0]

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    cluster_name = local.cluster_name
    node_type    = "user"
  }))

  # EBS volume configuration
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      kms_key_id           = aws_kms_key.ecr.arn
      delete_on_termination = true
    }
  }

  # Instance metadata service configuration
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Network interface configuration
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups            = [aws_security_group.eks_nodes.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-user-node"
      Type = "EKS-UserNode"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-user-node-volume"
      Type = "EBS-Volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-user-launch-template"
    Type = "LaunchTemplate"
  })
}