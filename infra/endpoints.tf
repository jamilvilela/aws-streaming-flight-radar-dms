# ---------------------------------------------------------------------------
# VPC Endpoint — S3 (Gateway)
# Para DMS escrever no S3 landing bucket via VPC
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.effective_vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [data.aws_vpc.selected.main_route_table_id]

  tags = merge(var.tags, {
    Name = "${var.project_name}-s3-vpce"
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoint — Secrets Manager (Interface via PrivateLink)
# DMS precisa acessar o Secrets Manager para credenciais do Aurora
# Por padrão usa apenas 1 subnet (1 AZ) para reduzir custo ($0.01/h por AZ).
# Para alta disponibilidade, defina secrets_vpce_subnet_ids com mais subnets.
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id            = local.effective_vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  subnet_ids         = var.secrets_vpce_subnet_ids != null ? var.secrets_vpce_subnet_ids : [local.effective_subnet_ids[0]]
  security_group_ids = [aws_security_group.secrets_endpoint.id]

  private_dns_enabled = true

  # Policy restritiva do endpoint: permite apenas leitura do secret do DMS
  # via PrivateLink (defense-in-depth).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowDMSSecretsManagerAccess"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [local.aurora_credentials_secret_arn]
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-secrets-vpce"
  })
}
