data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# VPC discovery — encontra a VPC pelo nome (tag Name)
# Se nenhuma VPC com o nome configurado existir, usa a default VPC como
# fallback. Evita expor vpc_id / subnet_ids em arquivos ou variáveis.
# ---------------------------------------------------------------------------
data "aws_vpcs" "by_name" {
  tags = {
    Name = var.vpc_name != null ? var.vpc_name : "${var.project_name}-vpc"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_vpc" "selected" {
  id = local.effective_vpc_id
}

# ---------------------------------------------------------------------------
# Subnets discovery — todas as subnets da VPC encontrada
# ---------------------------------------------------------------------------
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [local.effective_vpc_id]
  }
}

# ---------------------------------------------------------------------------
# Aurora RDS Cluster discovery — busca endpoint, porta e db_name
# a partir do cluster_identifier informado no tfvars.
# ---------------------------------------------------------------------------
data "aws_rds_cluster" "aurora" {
  cluster_identifier = var.aurora_cluster_identifier
}

# ---------------------------------------------------------------------------
# Aurora Security Group discovery — encontra o SG pelo nome
# O nome segue o padrão do módulo aurora_postgres: <project_name>-aurora-sg
# ---------------------------------------------------------------------------
data "aws_security_group" "aurora" {
  tags = {
    Name = "${var.project_name}-aurora-sg"
  }
}
