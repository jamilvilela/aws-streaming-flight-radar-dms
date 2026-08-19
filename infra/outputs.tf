# ============================================================================
# Aurora cluster info (descoberto via data source)
# Usado pelo deploy.sh para popular o secret do DMS
# ============================================================================

output "aurora_endpoint" {
  description = "Aurora cluster writer endpoint (discovered via data source)"
  value       = local.aurora_endpoint
}

output "aurora_port" {
  description = "Aurora cluster port (discovered via data source)"
  value       = local.aurora_port
}

output "aurora_db_name" {
  description = "Aurora database name (discovered via data source)"
  value       = local.aurora_db_name
}

# ============================================================================
# DMS Serverless outputs
# ============================================================================

output "dms_replication_config_arn" {
  description = "ARN of the DMS Serverless replication config"
  value       = aws_dms_replication_config.this.arn
}

output "dms_replication_config_id" {
  description = "ID of the DMS Serverless replication config"
  value       = aws_dms_replication_config.this.id
}

output "dms_replication_config_identifier" {
  description = "Identifier (name) of the DMS Serverless replication config"
  value       = aws_dms_replication_config.this.replication_config_identifier
}

output "dms_source_endpoint_arn" {
  description = "ARN of the DMS source endpoint (Aurora PostgreSQL)"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "dms_target_endpoint_arn" {
  description = "ARN of the DMS target endpoint (S3 Parquet)"
  value       = aws_dms_s3_endpoint.target.endpoint_arn
}

output "dms_security_group_id" {
  description = "DMS Serverless security group ID"
  value       = aws_security_group.dms.id
}
