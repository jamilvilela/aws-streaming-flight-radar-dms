# ---------------------------------------------------------------------------
# Secrets Manager — Aurora PostgreSQL credentials for DMS source endpoint
# O secret é gerenciado em secrets.tf:
#   - Se já existe com o nome configurado → é REUTILIZADO (não é sobrescrito).
#   - Se não existe → é CRIADO com as credenciais do .env (TF_VAR_db_*).
# O ARN efetivo é exposto via local.aurora_credentials_secret_arn.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# DMS subnet group
# DMS Serverless precisa de um subnet group para o compute_config
# ---------------------------------------------------------------------------
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.project_name}-dms-serverless-subnet-group"
  replication_subnet_group_description = "DMS Serverless subnet group for ${var.project_name}"
  subnet_ids                           = local.effective_subnet_ids

  # DMS requires the dms-vpc-role to exist before creating subnet groups
  depends_on = [aws_iam_role.dms_vpc_default]

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-subnet-group"
  })
}

# ---------------------------------------------------------------------------
# DMS source endpoint — Aurora PostgreSQL
# ---------------------------------------------------------------------------
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-dms-source-aurora"
  endpoint_type = "source"
  engine_name   = "aurora-postgresql"
  database_name = local.aurora_db_name
  ssl_mode      = "require"

  secrets_manager_access_role_arn = aws_iam_role.dms_s3.arn
  secrets_manager_arn             = local.aurora_credentials_secret_arn

  postgres_settings {
    capture_ddls = true
    # pglogical — plugin de replicação lógica para CDC no Aurora PostgreSQL
    plugin_name                  = "pglogical"
    fail_tasks_on_lob_truncation = false
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-source-aurora"
  })
}

# ---------------------------------------------------------------------------
# DMS target endpoint — S3 Parquet on landing bucket
# ---------------------------------------------------------------------------
resource "aws_dms_s3_endpoint" "target" {
  endpoint_id              = "${var.project_name}-dms-target-s3"
  endpoint_type            = "target"
  service_access_role_arn  = aws_iam_role.dms_s3.arn
  bucket_name              = local.landing_bucket_name
  bucket_folder            = "dms/${local.aurora_db_name}/"
  data_format              = "parquet"
  parquet_version          = "parquet-2-0"
  compression_type         = "gzip"
  date_partition_enabled   = true
  date_partition_sequence  = "YYYYMMDDHH"
  include_op_for_full_load = true
  cdc_max_batch_interval   = 30
  cdc_min_file_size        = 32000
  timestamp_column_name    = "dms_timestamp"
  preserve_transactions    = false
  glue_catalog_generation  = false

  cdc_path = "cdc/"

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-target-s3"
  })
}

# ---------------------------------------------------------------------------
# DMS Serverless replication config — full load + CDC
# ---------------------------------------------------------------------------
resource "aws_dms_replication_config" "this" {
  replication_config_identifier = "${var.project_name}-dms-serverless-config"
  source_endpoint_arn           = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn           = aws_dms_s3_endpoint.target.endpoint_arn
  replication_type              = "full-load-and-cdc"

  compute_config {
    replication_subnet_group_id  = aws_dms_replication_subnet_group.this.replication_subnet_group_id
    vpc_security_group_ids       = [aws_security_group.dms.id]
    max_capacity_units           = var.max_capacity_units
    min_capacity_units           = var.min_capacity_units
    multi_az                     = var.multi_az
    preferred_maintenance_window = "sun:06:00-sun:07:00"
  }

  # Regras de mapeamento explícitas — ver infra/table-mappings.json.
  # Seleciona APENAS as tabelas do schema flight_radar definidas em
  # hidden/sql-init-schema.sql. aircraft_positions é PARTICIONADA: a seleção
  # usa o wildcard aircraft_positions_% (as partições mensais) em vez do pai,
  # pois o DMS só captura CDC no PostgreSQL pelo relation id da partição filha
  # no WAL. Sem filtro de data (o DMS exige nome exato da tabela para filtros —
  # não combina com wildcard); o full load carrega a tabela completa.
  # Sem rename p/ "aircraft_positions": a AWS não suporta renomear múltiplas
  # tabelas-fonte para o mesmo folder no target S3. Cada partição vira um
  # prefixo próprio (ex: flight_radar/aircraft_positions_2026_08/).
  # Para sobrescrever por ambiente, defina a variável table_mappings no tfvars.
  table_mappings = var.table_mappings != null ? var.table_mappings : file("${path.module}/table-mappings.json")

  # Replication settings — ver infra/replication-settings.json.
  # TargetTablePrepMode = TRUNCATE_BEFORE_LOAD: para alvo S3, apaga os arquivos
  # existentes do folder da tabela antes do full load (exige s3:DeleteObject na
  # role) — evita dados duplicados/stale ao reiniciar full load + CDC.
  # Para sobrescrever por ambiente, defina a variável replication_settings.
  replication_settings = var.replication_settings != null ? var.replication_settings : file("${path.module}/replication-settings.json")

  # Don't auto-start — use AWS Console or CLI to start after validation
  start_replication = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-config"
  })

  # Evita "No modifications requested" causado por campos computados que a AWS
  # adiciona ao replication_settings e table_mappings (ex: BeforeImageSettings,
  # LoopbackPreventionSettings) que geram diff falso no plan.
  lifecycle {
    ignore_changes = [
      replication_settings,
      table_mappings,
    ]
  }
}
