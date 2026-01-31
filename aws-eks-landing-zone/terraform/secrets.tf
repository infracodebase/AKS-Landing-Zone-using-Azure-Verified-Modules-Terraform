# Secrets Manager secrets for application configuration
resource "aws_secretsmanager_secret" "database_credentials" {
  name                    = "${local.cluster_name}/database/credentials"
  description            = "Database credentials for EKS applications"
  kms_key_id             = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  replica {
    region = data.aws_region.current.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-secret"
    Type = "Secret"
  })
}

# Generate initial database credentials
resource "aws_secretsmanager_secret_version" "database_credentials" {
  secret_id = aws_secretsmanager_secret.database_credentials.id

  secret_string = jsonencode({
    username = "admin"
    password = random_password.database_password.result
    engine   = "mysql"
    host     = "localhost"
    port     = 3306
    dbname   = "myapp"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "random_password" "database_password" {
  length  = 32
  special = true
}

# API Keys secret
resource "aws_secretsmanager_secret" "api_keys" {
  name                    = "${local.cluster_name}/api/keys"
  description            = "API keys for external service integrations"
  kms_key_id             = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  replica {
    region = data.aws_region.current.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-keys-secret"
    Type = "Secret"
  })
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = aws_secretsmanager_secret.api_keys.id

  secret_string = jsonencode({
    external_service_api_key = "change-me-after-deployment"
    webhook_secret          = random_password.webhook_secret.result
    jwt_secret             = random_password.jwt_secret.result
    github_token           = "change-me-after-deployment"
    slack_webhook_url      = "change-me-after-deployment"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "random_password" "webhook_secret" {
  length  = 64
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# SSL/TLS certificates secret
resource "aws_secretsmanager_secret" "tls_certificates" {
  name                    = "${local.cluster_name}/tls/certificates"
  description            = "TLS certificates for applications"
  kms_key_id             = aws_kms_key.secrets_manager.arn
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tls-certificates"
    Type = "Secret"
  })
}

# SSM Parameters for cluster configuration
resource "aws_ssm_parameter" "cluster_config" {
  name  = "/${local.cluster_name}/cluster/config"
  type  = "String"
  value = jsonencode({
    cluster_name            = local.cluster_name
    environment            = var.environment
    region                 = var.aws_region
    ecr_repositories       = values(aws_ecr_repository.repositories)[*].repository_url
    log_retention_days     = var.log_retention_days
    monitoring_enabled     = var.enable_container_insights
    vpc_id                = module.vpc.vpc_id
    private_subnet_ids    = module.vpc.private_subnets
    public_subnet_ids     = module.vpc.public_subnets
    security_group_ids = {
      cluster = aws_security_group.eks_cluster.id
      nodes   = aws_security_group.eks_nodes.id
    }
  })
  description = "Cluster configuration parameters"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster-config"
    Type = "SSM-Parameter"
  })
}

# Container image pull configuration
resource "aws_ssm_parameter" "image_pull_config" {
  name  = "/${local.cluster_name}/container/image-pull"
  type  = "String"
  value = jsonencode({
    ecr_endpoint            = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
    image_pull_policy      = "IfNotPresent"
    scan_on_push           = var.enable_image_scanning
    lifecycle_policy_days  = var.lifecycle_policy_days
    repositories = {
      for k, v in aws_ecr_repository.repositories : k => {
        name = v.name
        url  = v.repository_url
      }
    }
  })
  description = "Container image pull configuration"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-image-pull-config"
    Type = "SSM-Parameter"
  })
}

# Application environment configuration
resource "aws_ssm_parameter" "app_environment" {
  name  = "/${local.cluster_name}/app/environment"
  type  = "String"
  value = jsonencode({
    environment     = var.environment
    log_level      = var.environment == "prod" ? "INFO" : "DEBUG"
    debug_mode     = var.environment != "prod"
    metrics_enabled = true
    tracing_enabled = true
    health_check = {
      enabled  = true
      path     = "/health"
      interval = "30s"
    }
  })
  description = "Application environment configuration"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-environment"
    Type = "SSM-Parameter"
  })
}

# Network configuration for applications
resource "aws_ssm_parameter" "network_config" {
  name  = "/${local.cluster_name}/network/config"
  type  = "String"
  value = jsonencode({
    vpc_cidr               = var.vpc_cidr
    private_subnet_cidrs  = var.private_subnet_cidrs
    public_subnet_cidrs   = var.public_subnet_cidrs
    dns_servers = [
      "169.254.169.253", # Amazon DNS
      "8.8.8.8"          # Google DNS fallback
    ]
    load_balancer = {
      type                = "application"
      scheme             = "internal"
      enable_cross_zone  = true
    }
  })
  description = "Network configuration for applications"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-network-config"
    Type = "SSM-Parameter"
  })
}

# Monitoring and observability configuration
resource "aws_ssm_parameter" "monitoring_config" {
  name  = "/${local.cluster_name}/monitoring/config"
  type  = "String"
  value = jsonencode({
    cloudwatch = {
      enabled            = var.enable_container_insights
      log_group         = aws_cloudwatch_log_group.cluster.name
      retention_days    = var.log_retention_days
    }
    prometheus = {
      enabled           = false
      namespace         = "prometheus"
      scrape_interval  = "30s"
    }
    jaeger = {
      enabled     = false
      namespace   = "jaeger"
    }
  })
  description = "Monitoring and observability configuration"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-monitoring-config"
    Type = "SSM-Parameter"
  })
}