aws_region   = "us-east-1"
project_name = "flight-radar-stream"
environment  = "production"

buckets = {
  workspace = "lakehouse-workspace"
  raw       = "lakehouse-raw"
  landing   = "lakehouse-landing"
  trusted   = "lakehouse-trusted"
  business  = "lakehouse-business"
}

tags = {
  Environment = "production"
  Project     = "flight-radar-stream"
  ManagedBy   = "terraform"
}

# ── Networking ──────────────────────────────────────────────────────────────
# A VPC é descoberta automaticamente pelo tag Name (default: <project_name>-vpc).
# Opcional: descomente abaixo para usar uma VPC com nome diferente.
# vpc_name = "default-vpc"

# ── External Aurora PostgreSQL ─────────────────────────────────────────────
# O cluster Aurora é descoberto via Terraform data source.
# Basta informar o cluster_identifier — endpoint, porta, db_name e
# security group são obtidos automaticamente.
aurora_cluster_identifier = "flight-radar-stream-aurora"

# ── DMS Serverless ────────────────────────────────────────────────────────
min_capacity_units = 2
max_capacity_units = 8
multi_az           = false
log_retention_days = 7
create_kms_key     = true

