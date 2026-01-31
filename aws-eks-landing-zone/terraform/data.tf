# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for AWS partition (commercial, gov, china)
data "aws_partition" "current" {}

# Data source for EKS cluster auth
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.eks_cluster_id
}

# Data source for latest Amazon Linux 2 EKS optimized AMI
data "aws_ami" "eks_worker" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.kubernetes_version}-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Data source for EKS OIDC root CA thumbprint
data "tls_certificate" "eks_oidc" {
  url = module.eks_cluster.eks_cluster_identity_oidc_issuer
}

# Data source for getting the current user for tagging
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}