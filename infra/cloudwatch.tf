# ---------------------------------------------------------------------------
# CloudWatch log group for DMS Serverless
# DMS Serverless cria logs em dms-replication-config-<config-id> automaticamente
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "dms" {
  name              = "dms-replication-config-${var.project_name}-dms-serverless-config"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-dms-serverless-log-group"
  })
}

# ---------------------------------------------------------------------------
# CloudWatch Dashboard — monitoramento do pipeline DMS
# Métricas-chave para acompanhar throughput de CDC em tempo real
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
            ["AWS/DMS", "CDCChangesThroughput", "ReplicationConfigIdentifier",
            "${var.project_name}-dms-serverless-config"],
            ["AWS/DMS", "CDCChangesThroughput", "ReplicationConfigIdentifier",
            "${var.project_name}-dms-serverless-config", { stat = "Average" }],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "CDC Changes Throughput (bytes/s)"
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
            ["AWS/DMS", "CDCChangesCount", "ReplicationConfigIdentifier",
            "${var.project_name}-dms-serverless-config"],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "CDC Changes Count (records/s)"
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
            ["AWS/DMS", "CpuUsage", "ReplicationConfigIdentifier",
            "${var.project_name}-dms-serverless-config"],
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
            ["AWS/DMS", "FreeMemory", "ReplicationConfigIdentifier",
            "${var.project_name}-dms-serverless-config"],
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "Free Memory (MB)"
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
            ["AWS/DMS", "CDCLatencyTarget", "ReplicationConfigIdentifier",
            "${var.project_name}-dms-serverless-config"],
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
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName",
            local.landing_bucket_name, { stat = "Average" }],
            ["AWS/S3", "NumberOfObjects", "BucketName",
            local.landing_bucket_name, { stat = "Average" }],
          ]
          period = 3600
          stat   = "Average"
          region = var.aws_region
          title  = "S3 Landing Bucket Growth"
        }
      },
    ]
  })
}
