# =============================================================================
# Secrets Manager — Aurora credentials for the DMS source endpoint
#
# Comportamento (idempotente):
#   - Se um secret com o mesmo nome (local.aurora_credentials_secret_name)
#     JÁ EXISTE no Secrets Manager → ele é REUTILIZADO (não é sobrescrito,
#     não é destruído, nenhuma versão é alterada).
#   - Se NÃO existe → o secret é CRIADO com as credenciais vindas do .env
#     (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD → TF_VAR_db_*).
#
# O ARN efetivo é exposto via local.aurora_credentials_secret_arn e usado
# pelo source endpoint do DMS (main.tf) e pela policy IAM do role dms_s3
# (iam.tf).
#
# ⚠️ Nota sobre o padrão "create if not exists":
#   - Secret existente → count = 0 → nada é criado/destruído.
#   - Secret inexistente → count = 1 → criamos secret + versão + policy.
#   - Se o Terraform criou o secret e um apply posterior detectar que ele
#     existe, o count vai para 0 e o recurso sairia do gerenciamento.
#     Para manter o secret gerenciado nesse caso, importe-o:
#       terraform import 'aws_secretsmanager_secret.aurora_credentials[0]' <arn>
# =============================================================================

# Detecta se já existe um secret com o nome configurado.
# O data source plural NÃO falha quando nada é encontrado (retorna lista vazia).
data "aws_secretsmanager_secrets" "existing" {
  filter {
    name   = "name"
    values = [local.aurora_credentials_secret_name]
  }
}

# Cria o secret APENAS se ele ainda não existir.
resource "aws_secretsmanager_secret" "aurora_credentials" {
  count = length(data.aws_secretsmanager_secrets.existing.arns) == 0 ? 1 : 0

  name        = local.aurora_credentials_secret_name
  description = "Aurora PostgreSQL credentials for DMS source endpoint (${var.project_name})"

  tags = merge(var.tags, {
    Name = local.aurora_credentials_secret_name
  })
}

# Versão do secret com as credenciais do Aurora (do .env).
# Só é criada junto com o secret (mesmo count).
resource "aws_secretsmanager_secret_version" "aurora_credentials" {
  count = length(data.aws_secretsmanager_secrets.existing.arns) == 0 ? 1 : 0

  secret_id = aws_secretsmanager_secret.aurora_credentials[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
  })
}

# Resource-based policy no secret: permite o role DMS ler o valor.
# (Defense-in-depth — o role dms_s3 já possui policy IAM com GetSecretValue.)
resource "aws_secretsmanager_secret_policy" "aurora_credentials" {
  count = length(data.aws_secretsmanager_secrets.existing.arns) == 0 ? 1 : 0

  secret_arn = aws_secretsmanager_secret.aurora_credentials[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDMSReadSecret"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.dms_s3.arn
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [aws_secretsmanager_secret.aurora_credentials[0].arn]
      }
    ]
  })
}

# ARN efetivo do secret: o existente (se houver) ou o recém-criado.
# (arns do data source é um set — convertido com tolist() para indexar)
locals {
  aurora_credentials_secret_arn = length(data.aws_secretsmanager_secrets.existing.arns) > 0 ? tolist(data.aws_secretsmanager_secrets.existing.arns)[0] : aws_secretsmanager_secret.aurora_credentials[0].arn
}