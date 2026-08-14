variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ── Networking ──────────────────────────────────────────────────────────────

variable "vpc_name" {
  description = "Name tag of the VPC to use (default: \"<project_name>-vpc\")"
  type        = string
  default     = null
}

variable "secrets_vpce_subnet_ids" {
  description = "Subnet IDs for the Secrets Manager VPC Endpoint. Default: 1 subnet (1 AZ) to reduce cost. Each AZ adds $0.01/h."
  type        = list(string)
  default     = null
}

# ── S3 buckets ──────────────────────────────────────────────────────────────

variable "buckets" {
  description = "Map of S3 bucket names for different purposes"
  type        = map(string)
}

# ── External Aurora PostgreSQL (managed by sister repo) ────────────────────
# O cluster Aurora é descoberto via Terraform data source a partir do
# cluster_identifier. Endpoint, porta, db_name e security group são
# obtidos automaticamente — não é necessário expor esses valores.

variable "aurora_cluster_identifier" {
  description = "Identifier of the existing Aurora cluster (discovered via data source)"
  type        = string
}

variable "db_secret_name" {
  description = "Name of the existing Secrets Manager secret with Aurora credentials for the DMS source endpoint. Set via .env (DB_SECRET_NAME → TF_VAR_db_secret_name). Default: \"<project_name>/aurora-credentials\""
  type        = string
  default     = null
}

# ── Aurora credentials (do .env → TF_VAR_db_*) ─────────────────────────────
# Usadas para CRIAR o secret no Secrets Manager quando ele ainda não existe.
# Se o secret já existir, estes valores não são utilizados.

variable "db_host" {
  description = "Aurora cluster writer endpoint host (from .env DB_HOST → TF_VAR_db_host). Used to create the secret when it doesn't exist."
  type        = string
  default     = null
}

variable "db_port" {
  description = "Aurora cluster port (from .env DB_PORT → TF_VAR_db_port). Used to create the secret when it doesn't exist."
  type        = string
  default     = null
}

variable "db_name" {
  description = "Aurora database name (from .env DB_NAME → TF_VAR_db_name). Used to create the secret when it doesn't exist."
  type        = string
  default     = null
}

variable "db_username" {
  description = "Aurora database username (from .env DB_USER → TF_VAR_db_username). Used to create the secret when it doesn't exist."
  type        = string
  default     = null
}

variable "db_password" {
  description = "Aurora database password (from .env DB_PASSWORD → TF_VAR_db_password). Used to create the secret when it doesn't exist."
  type        = string
  default     = null
  sensitive   = true
}

# ── DMS Serverless configuration ───────────────────────────────────────────

variable "min_capacity_units" {
  description = "Minimum DMS Serverless capacity units"
  type        = number
  default     = 2
}

variable "max_capacity_units" {
  description = "Maximum DMS Serverless capacity units"
  type        = number
  default     = 8
}

variable "multi_az" {
  description = "Enable Multi-AZ for DMS Serverless"
  type        = bool
  default     = false
}

variable "table_mappings" {
  description = "DMS table mappings JSON (selection rules, transformations). Default: infra/table-mappings.json (tabelas explícitas do schema flight_radar + filtro de data >= 2026-01-01 no full load de aircraft_positions)"
  type        = string
  default     = null
}

variable "replication_settings" {
  description = "DMS replication settings JSON (task settings)"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "create_kms_key" {
  description = "Whether to create a KMS key for DMS encryption"
  type        = bool
  default     = true
}
