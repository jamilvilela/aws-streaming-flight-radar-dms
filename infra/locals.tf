locals {
  # ── VPC e subnets descobertas via data sources ──
  # Usa a VPC por nome se existir; senão cai para a default VPC
  effective_vpc_id     = length(data.aws_vpcs.by_name.ids) > 0 ? data.aws_vpcs.by_name.ids[0] : data.aws_vpc.default.id
  effective_subnet_ids = data.aws_subnets.selected.ids

  # ── Aurora cluster info descoberta via data source ──
  aurora_endpoint          = data.aws_rds_cluster.aurora.endpoint
  aurora_port              = data.aws_rds_cluster.aurora.port
  aurora_db_name           = data.aws_rds_cluster.aurora.database_name
  aurora_security_group_id = data.aws_security_group.aurora.id

  # ── Buckets com sufixo do account ID ──
  buckets = merge(
    var.buckets,
    {
      workspace = "${var.buckets.workspace}-${data.aws_caller_identity.current.account_id}"
      landing   = "${var.buckets.landing}-${data.aws_caller_identity.current.account_id}"
      raw       = "${var.buckets.raw}-${data.aws_caller_identity.current.account_id}"
      trusted   = "${var.buckets.trusted}-${data.aws_caller_identity.current.account_id}"
      business  = "${var.buckets.business}-${data.aws_caller_identity.current.account_id}"
    }
  )

  # ── Landing bucket name with account suffix (convenience) ──
  landing_bucket_name = local.buckets.landing

  # ── Secret existente com credenciais do Aurora para o source endpoint do DMS ──
  # Gerenciado externamente (não é criado nem alterado pelo deploy.sh).
  aurora_credentials_secret_name = var.db_secret_name != null ? var.db_secret_name : "${var.project_name}/aurora-credentials"

  # ── DMS Serverless publica métricas CloudWatch com a dimensão:
  #    ReplicationConfigId = "<account-id>:<sufixo-do-arn-do-replication-config>"
  # (NÃO usa ReplicationConfigIdentifier). Derivado do ARN para o dashboard.
  dms_replication_config_id = "${data.aws_caller_identity.current.account_id}:${element(split(":", aws_dms_replication_config.this.arn), -1)}"
}
