# ---------------------------------------------------------------------------
# CloudWatch log group para DMS Serverless
# O DMS Serverless SEMPRE escreve logs em dms-serverless-replication-<sufixo do
# ARN> (auto-cria se não existir) — não aceita nome customizado. Este recurso
# garante retention e existência prévia com o nome real derivado do ARN.
# (O nome antigo dms-replication-config-<identifier> nunca é usado pelo DMS.)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "dms" {
  name              = "dms-serverless-replication-${element(split(":", aws_dms_replication_config.this.arn), -1)}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-log-group"
  })
}

# ---------------------------------------------------------------------------
# CloudWatch Dashboard — monitoramento do pipeline DMS Serverless
# Métricas-chave para acompanhar throughput de full load e CDC em tempo real
#
# ATENÇÃO: o DMS Serverless publica métricas com dimensão
#   ReplicationConfigId = "<account-id>:<sufixo do ARN>"
# e com nomes próprios do serverless (CDCThroughputBandwidthTarget,
# CDCIncomingChanges, CPUUtilization, CapacityUtilization, CDCLatencyTarget,
# FullLoadThroughput*). Os nomes do DMS clássico (CDCChangesThroughput,
# CDCChangesCount, CpuUsage, FreeMemory) NÃO são publicados no serverless —
# por isso o dashboard anterior não exibia dados.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "dms" {
  dashboard_name = "${var.project_name}-dms-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "CDCThroughputBandwidthTarget", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "CDC Throughput to target (bytes/s)"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "CDCIncomingChanges", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "CDC Changes incoming (records/s)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "CPUUtilization", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "CPU Usage (%)"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "CapacityUtilization", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "Capacity Utilization (%)"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "CDCLatencyTarget", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "CDC Target Latency (s)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "FullLoadThroughputRowsTarget", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "Full Load Throughput (rows/s)"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DMS", "FullLoadThroughputBandwidthTarget", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "Full Load Throughput (bytes/s)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          # Métricas diárias do S3 (BucketSizeBytes/NumberOfObjects) só
          # aparecem em ranges de dias (1 publicação/dia ~03:00 UTC) — no range
          # Live ficam vazias. Usamos throughput do DMS para o alvo S3 (a cada
          # minuto) como indicador real-time do landing.
          metrics = [
            ["AWS/DMS", "FullLoadThroughputRowsTarget", "ReplicationConfigId",
            local.dms_replication_config_id],
            ["AWS/DMS", "CDCThroughputRowsTarget", "ReplicationConfigId",
            local.dms_replication_config_id],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "Rows landing in S3 (Full Load + CDC, rows/s)"
        }
      },
    ]
  })
}
