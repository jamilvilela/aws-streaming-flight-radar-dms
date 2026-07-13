# aws-streaming-flight-radar-dms

**AWS DMS Serverless** — Pipeline de replicação de dados de voos do Aurora PostgreSQL para S3 (Parquet) via DMS com captura CDC.

> ⚠️ **Nota:** O cluster Aurora PostgreSQL é gerenciado externamente (repositório `aws-streaming-flight-radar-aurora-dms`).
> Este repositório contém apenas os recursos auxiliares do DMS Serverless (IAM, KMS, CloudWatch, Security Groups, VPC Endpoints)
> e a configuração de replicação propriamente dita.

## Serviço

| Serviço | Descrição |
|---------|-----------|
| **AWS DMS Serverless** | Replicação Full Load + CDC do Aurora (externo) para S3 no formato Parquet |

## Recursos implantados

| Recurso | Descrição |
|---------|-----------|
| **DMS Serverless** | Replication config (full-load-and-cdc) com endpoints source (Aurora) e target (S3) |
| **IAM Roles** | `dms-s3-role` (acesso ao S3 e Secrets Manager) e `dms-vpc-role` (gerenciamento VPC) |
| **KMS Key** | Chave gerenciada para criptografia do DMS |
| **CloudWatch** | Log group e Dashboard de monitoramento do pipeline |
| **Security Groups** | SG para DMS e VPC Endpoint do Secrets Manager |
| **VPC Endpoints** | Gateway S3 + Interface Secrets Manager (PrivateLink) |

## Estrutura

```
infra/                     # Terraform (recursos DMS Serverless)
├── main.tf                # Recursos principais (subnet group, endpoints, replication config)
├── variables.tf           # Variáveis de entrada
├── outputs.tf             # Outputs do stack
├── providers.tf           # Provider AWS
├── data.tf                # Data sources
├── locals.tf              # Locals
├── iam.tf                 # IAM roles e policies
├── kms.tf                 # KMS key
├── cloudwatch.tf          # Log group e dashboard
├── security_groups.tf     # Security groups
├── endpoints.tf           # VPC endpoints (S3 Gateway + Secrets Manager Interface)
├── tfvars/
│   └── terraform.tfvars   # Valores das variáveis

setup-env.sh               # Deploy automatizado (Terraform)
rollback-setup.sh          # Destrói recursos (Terraform destroy)
```

## Pré-requisitos

- Cluster Aurora PostgreSQL existente (gerenciado externamente)
- Secrets Manager secret: `<project_name>-dms-aurora-credentials` (criado automaticamente pelo `setup-env.sh`)
- Bucket S3 de landing zone existente
- VPC com subnets privadas para o DMS Serverless

## Deploy rápido

```bash
# 1. Configure .env
cp .env.example .env
# Edite .env com AWS_REGION

# 2. Configure tfvars
# Edite infra/tfvars/terraform.tfvars:
#   - vpc_id, subnet_ids
#   - aurora_endpoint, aurora_port, aurora_db_name, aurora_security_group_id
#   - min/max_capacity_units

# 3. Deploy
./setup-env.sh
```

## Destruir recursos

```bash
./rollback-setup.sh
```
