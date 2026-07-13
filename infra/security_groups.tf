# ---------------------------------------------------------------------------
# DMS security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "dms" {
  name        = "${var.project_name}-dms-serverless-sg"
  description = "Security group for DMS Serverless"
  vpc_id      = local.effective_vpc_id

  ingress {
    from_port       = local.aurora_port
    to_port         = local.aurora_port
    protocol        = "tcp"
    security_groups = [local.aurora_security_group_id]
    description     = "Allow inbound from Aurora PostgreSQL security group"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound to AWS services (S3, CloudWatch, Secrets Manager, KMS)"
  }

  egress {
    from_port   = local.aurora_port
    to_port     = local.aurora_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "Allow outbound to Aurora PostgreSQL"
  }

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

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
    description     = "Allow HTTPS from DMS Serverless"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-secrets-vpce-sg"
  })
}

# ---------------------------------------------------------------------------
# Allow DMS to access Aurora PostgreSQL on port 5432
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
