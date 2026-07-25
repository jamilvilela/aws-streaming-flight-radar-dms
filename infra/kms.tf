# ---------------------------------------------------------------------------
# KMS Key for DMS encryption
# ---------------------------------------------------------------------------
resource "aws_kms_key" "dms" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for DMS Serverless ${var.project_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "dms" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.project_name}-dms-serverless"
  target_key_id = aws_kms_key.dms[0].key_id
}
