locals {
  # ── VPC e subnets descobertas via data sources ──
  effective_vpc_id    = data.aws_vpc.selected.id
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
}
