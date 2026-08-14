# ---------------------------------------------------------------------------
# DMS security group
# Todas as regras são gerenciadas via aws_security_group_rule (sem blocos
# inline) porque os SGs referenciam-se mutuamente (dms <-> secrets_endpoint).
# Misturar bloco inline + regra standalone no mesmo SG gera drift no provider
# e blocos inline com referência cruzada criam ciclo de dependência.
# ---------------------------------------------------------------------------
resource "aws_security_group" "dms" {
  name        = "${var.project_name}-dms-serverless-sg"
  description = "Security group for DMS Serverless"
  vpc_id      = local.effective_vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-sg"
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoint — Secrets Manager (Interface via PrivateLink) security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "secrets_endpoint" {
  name        = "${var.project_name}-dms-serverless-secrets-vpce-sg"
  description = "Security group for Secrets Manager VPC Endpoint (DMS Serverless)"
  vpc_id      = local.effective_vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-secrets-vpce-sg"
  })
}

# ── DMS: ingress from Aurora security group ───────────────────────────────
resource "aws_security_group_rule" "dms_from_aurora" {
  type                     = "ingress"
  from_port                = local.aurora_port
  to_port                  = local.aurora_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dms.id
  source_security_group_id = local.aurora_security_group_id
  description              = "Allow inbound from Aurora PostgreSQL security group"
}

# ── DMS: egress HTTPS genérico para AWS services ──────────────────────────
resource "aws_security_group_rule" "dms_to_aws_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.dms.id
  description       = "Allow HTTPS outbound to AWS services (S3, CloudWatch, Secrets Manager, KMS)"
}

# ── DMS: egress para o VPC Endpoint do Secrets Manager ────────────────────
# (defense-in-depth — além da regra genérica 443/0.0.0.0/0)
resource "aws_security_group_rule" "dms_to_secrets_endpoint" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dms.id
  source_security_group_id = aws_security_group.secrets_endpoint.id
  description              = "DMS Serverless to Secrets Manager VPC Endpoint"
}

# ── DMS: egress para Aurora PostgreSQL (CIDR da VPC) ──────────────────────
resource "aws_security_group_rule" "dms_to_aurora_cidr" {
  type              = "egress"
  from_port         = local.aurora_port
  to_port           = local.aurora_port
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.dms.id
  description       = "Allow outbound to Aurora PostgreSQL"
}

# ── Secrets endpoint: ingress HTTPS from DMS ──────────────────────────────
resource "aws_security_group_rule" "secrets_endpoint_from_dms" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.secrets_endpoint.id
  source_security_group_id = aws_security_group.dms.id
  description              = "Allow HTTPS from DMS Serverless"
}

# ---------------------------------------------------------------------------
# Allow DMS to access Aurora PostgreSQL on port 5432 (ingress no SG do Aurora)
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "dms_to_aurora" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dms.id
  security_group_id        = local.aurora_security_group_id
  description              = "DMS Serverless to Aurora PostgreSQL"
}