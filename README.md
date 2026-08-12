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

## Tabelas migradas (definidas explicitamente)

O DMS **não** usa mais seleção por wildcard (`schema-name = "%"` / `table-name = "%"`).
As tabelas migradas são definidas explicitamente em `infra/table-mappings.json`,
conforme o schema `flight_radar` do `hidden/sql-init-schema.sql`:

| Tabela | Origem | Observações |
|--------|--------|-------------|
| `countries` | countries.csv (OurAirports) | Referência |
| `aircraft_types` | airplanes.csv (OpenFlights) | Catálogo de modelos |
| `airports` | airports.csv (OurAirports) | Referência |
| `airlines` | airlines.csv (OpenFlights) | Referência |
| `routes` | routes.csv (OpenFlights) | Referência |
| `aircraft` | Gerada dinamicamente | Aeronaves individuais |
| `flights` | Gerada dinamicamente | Tabela fato de voos |
| `aircraft_positions` | Gerada dinamicamente (PARTITIONED) | Fato de altíssimo volume |

### Filtro de data no Full Load — `aircraft_positions`

A tabela `aircraft_positions` é selecionada apenas pela tabela **pai** (partições
mensais não são selecionadas individualmente, evitando output duplicado no S3).
A regra de seleção inclui um *source filter* que limita a carga full (e o CDC) a
registros com `recorded_at >= 2026-01-01`:

```json
{
  "filter-type": "source",
  "column-name": "recorded_at",
  "filter-conditions": [
    { "filter-operator": "gte", "value": "2026-01-01" }
  ]
}
```

> **Nota (limitações AWS DMS p/ PostgreSQL particionado):** o DMS não replica
> metadados de particionamento — no target S3 a tabela é gravada como tabela
> padrão (não particionada). DDL de partição (`ADD`/`DROP`/`TRUNCATE`) não é
> capturado no CDC.

## Estrutura

```
infra/                     # Terraform (recursos DMS Serverless)
├── main.tf                # Recursos principais (subnet group, endpoints, replication config)
├── table-mappings.json    # Definição explícita das tabelas migradas + filtros (source of truth)
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
- Secrets Manager secret existente com credenciais do Aurora (nome definido via `DB_SECRET_NAME` no `.env` — gerenciado externamente, o `setup-env.sh` não cria nem altera)
- Bucket S3 de landing zone existente
- VPC com subnets privadas para o DMS Serverless

## Deploy rápido

```bash
# 1. Configure .env
cp .env.example .env
# Preencha DB_SECRET_NAME com o nome do secret existente do DMS (não é versionado)

# 2. Configure tfvars
cp infra/tfvars/terraform.tfvars.example infra/tfvars/terraform.tfvars
# Edite infra/tfvars/terraform.tfvars:
#   - aurora_cluster_identifier (obrigatório)
#   - vpc_name (opcional, default: <project_name>-vpc)
# (terraform.tfvars não é versionado — o nome do secret fica no .env)

# 3. Deploy
./setup-env.sh
```

## Destruir recursos

```bash
./rollback-setup.sh
```
