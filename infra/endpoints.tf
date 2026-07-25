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
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id            = local.effective_vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.effective_subnet_ids
  security_group_ids = [aws_security_group.secrets_endpoint.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-secrets-vpce"
  })
}
