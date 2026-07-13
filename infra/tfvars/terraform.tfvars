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

# ── External Aurora PostgreSQL ─────────────────────────────────────────────
aurora_cluster_identifier = "flight-radar-stream-aurora"

# ── DMS Serverless ────────────────────────────────────────────────────────
min_capacity_units = 2
max_capacity_units = 8
multi_az           = false
log_retention_days = 7
create_kms_key     = true

