# VPC Module - Using the popular terraform-aws-modules/vpc
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # Enable DNS hostnames and resolution
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable NAT gateways for private subnet internet access
  enable_nat_gateway = true
  single_nat_gateway = false # Use one NAT Gateway per AZ for HA
  enable_vpn_gateway = false

  # Enable VPC Flow Logs
  enable_flow_log                      = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_log_group = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_iam_role  = var.enable_vpc_flow_logs
  flow_log_destination_type            = "cloud-watch-logs"
  flow_log_cloudwatch_log_group_retention_in_days = var.vpc_flow_logs_retention

  # Public subnet configuration
  public_subnet_tags = {
    Type                                        = "Public"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  # Private subnet configuration
  private_subnet_tags = {
    Type                                        = "Private"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }

  # VPC tags
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
    Type = "VPC"
  })

  # Additional VPC tags for EKS
  vpc_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  # Internet gateway tags
  igw_tags = {
    Name = "${local.name_prefix}-igw"
    Type = "InternetGateway"
  }

  # NAT gateway tags
  nat_gateway_tags = {
    Name = "${local.name_prefix}-natgw"
    Type = "NATGateway"
  }

  # NAT EIP tags
  nat_eip_tags = {
    Name = "${local.name_prefix}-eip-natgw"
    Type = "EIP"
  }

  # Public route table tags
  public_route_table_tags = {
    Name = "${local.name_prefix}-rt-public"
    Type = "RouteTable-Public"
  }

  # Private route table tags
  private_route_table_tags = {
    Name = "${local.name_prefix}-rt-private"
    Type = "RouteTable-Private"
  }
}

# Additional subnets for VPC endpoints (if needed)
resource "aws_subnet" "vpc_endpoints" {
  count = length(var.endpoints_subnet_cidrs) > 0 ? length(var.endpoints_subnet_cidrs) : 0

  vpc_id            = module.vpc.vpc_id
  cidr_block        = var.endpoints_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoints-${local.azs[count.index]}"
    Type = "VPC-Endpoints"
  })
}

# Route table for VPC endpoints subnets
resource "aws_route_table" "vpc_endpoints" {
  count = length(aws_subnet.vpc_endpoints) > 0 ? 1 : 0

  vpc_id = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-endpoints"
    Type = "RouteTable-Endpoints"
  })
}

# Associate VPC endpoints subnets with route table
resource "aws_route_table_association" "vpc_endpoints" {
  count = length(aws_subnet.vpc_endpoints)

  subnet_id      = aws_subnet.vpc_endpoints[count.index].id
  route_table_id = aws_route_table.vpc_endpoints[0].id
}

# Security Groups
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${local.name_prefix}-cluster-"
  description = "EKS cluster security group"
  vpc_id      = module.vpc.vpc_id

  # Allow inbound HTTPS from worker nodes
  ingress {
    description     = "HTTPS from worker nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster-sg"
    Type = "SecurityGroup"
  })
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${local.name_prefix}-nodes-"
  description = "EKS worker nodes security group"
  vpc_id      = module.vpc.vpc_id

  # Allow communication from EKS cluster
  ingress {
    description     = "Communication from EKS cluster"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Allow HTTPS from EKS cluster
  ingress {
    description     = "HTTPS from EKS cluster"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Allow all traffic between worker nodes
  ingress {
    description = "Node-to-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nodes-sg"
    Type = "SecurityGroup"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name_prefix}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  # Allow HTTPS from VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow DNS from VPC
  ingress {
    description = "DNS from VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "DNS UDP from VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
    Type = "SecurityGroup"
  })
}

# VPC Endpoints for private connectivity
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = module.vpc.vpc_id
  service_name    = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = module.vpc.private_route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
    Type = "VPC-Endpoint-Gateway"
  })
}

# Interface VPC Endpoints
resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each = {
    for k, v in local.vpc_endpoints : k => v
    if v.service_type == "Interface"
  }

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value.service_name}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "*"
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-endpoint"
    Type = "VPC-Endpoint-Interface"
  })
}