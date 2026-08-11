# ---------------------------------------------------------------------------
# Secrets Manager — Aurora PostgreSQL credentials for DMS source endpoint
# O secret é criado pelo setup-env.sh (via AWS CLI) antes do apply.
# O Terraform apenas lê o secret existente — não gerencia ciclo de vida.
# ---------------------------------------------------------------------------
data "aws_secretsmanager_secret" "aurora_credentials" {
  name = "${var.project_name}-dms-aurora-credentials"
}

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
  secrets_manager_arn             = data.aws_secretsmanager_secret.aurora_credentials.arn

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
  # hidden/sql-init-schema.sql, e aplica source filter de data no full load
  # (e CDC) da tabela particionada aircraft_positions:
  #   recorded_at >= 2026-01-01 (filter-operator: gte)
  # Para sobrescrever por ambiente, defina a variável table_mappings no tfvars.
  table_mappings = var.table_mappings != null ? var.table_mappings : file("${path.module}/table-mappings.json")

  replication_settings = var.replication_settings != null ? var.replication_settings : jsonencode({
    TargetMetadata = {
      SupportLobs        = true
      FullLobMode        = false
      LimitedSizeLobMode = true
      LobMaxSize         = 32
      LobChunkSize       = 64
      InlineLobMaxSize   = 0
      LoadMaxFileSize    = 0
    }
    ErrorBehavior = {
      FailOnNoTablesCaptured             = false
      FailOnTransactionConsistencyBreach = false
    }
    FullLoadSettings = {
      TargetTablePrepMode             = "DO_NOTHING"
      StopTaskCachedChangesNotApplied = false
      StopTaskCachedChangesApplied    = false
      MaxFullLoadSubTasks             = 8
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        { Id = "TRANSFORMATION", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SOURCE_UNLOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "IO", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_LOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "PERFORMANCE", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SOURCE_CAPTURE", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "SORTER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "REST_SERVER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "VALIDATOR_EXT", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_APPLY", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TASK_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TABLES_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "METADATA_MANAGER", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "FILE_FACTORY", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "COMMON", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "ADDONS", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "DATA_STRUCTURE", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "COMMUNICATION", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "FILE_TRANSFER", Severity = "LOGGER_SEVERITY_DEFAULT" }
      ]
    }
  })

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
