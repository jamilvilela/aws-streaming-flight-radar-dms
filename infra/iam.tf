# ---------------------------------------------------------------------------
# IAM roles for DMS
# ---------------------------------------------------------------------------
resource "aws_iam_role" "dms_s3" {
  name = "${var.project_name}-dms-serverless-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.${var.aws_region}.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "dms_s3" {
  name = "${var.project_name}-dms-serverless-s3-policy"
  role = aws_iam_role.dms_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:ListBucket",
            "s3:GetBucketLocation",
          ]
          Resource = [
            "arn:aws:s3:::${local.landing_bucket_name}",
            "arn:aws:s3:::${local.landing_bucket_name}/*",
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret",
          ]
          Resource = [local.aurora_credentials_secret_arn]
        },
      ],
      var.create_kms_key ? [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:GenerateDataKey",
          ]
          Resource = [aws_kms_key.dms[0].arn]
        },
      ] : []
    )
  })
}

# The default dms-vpc-role that DMS expects for VPC management
resource "aws_iam_role" "dms_vpc_default" {
  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.${var.aws_region}.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc_default" {
  role       = aws_iam_role.dms_vpc_default.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}
