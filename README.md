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

### Mapeamento da tabela particionada — `aircraft_positions`

`aircraft_positions` é **particionada por mês** (`PARTITION BY RANGE (recorded_at)`).
O DMS **não captura CDC pela tabela pai**: no WAL do PostgreSQL, cada DML é
registrado com o relation id da **partição filha** onde a linha foi gravada.
Por isso o table mapping seleciona as **partições** via wildcard
`aircraft_positions_%` (e não a tabela pai `aircraft_positions`), o que faz o
full load e o CDC de todas as partições funcionarem.

> **Nota (limitações AWS DMS):**
> - Selecionar apenas a tabela **pai** de uma tabela particionada funciona no
>   full load, mas **não captura CDC** (AWS: *"Including the parent table in the
>   mapping rule doesn't result in changes being replicated during the CDC
>   phase"*). Por isso usamos o wildcard das partições.
> - **Filtros source exigem nome exato da tabela** — não combinam com wildcard
>   (`Filters only support tables with exact names. Filters do not support
>   wildcards`). Por isso o full load de `aircraft_positions` carrega a tabela
>   completa (sem filtro de `recorded_at`).
> - A AWS **não suporta renomear múltiplas tabelas-fonte para o mesmo folder**
>   no target S3 (regra de transformação `rename`). Assim, cada partição grava
>   em um prefixo próprio, ex.: `flight_radar/aircraft_positions_2026_08/`
>   (com subpastas de data `YYYY/MM/DD/HH` para CDC). Para consolidar em um
>   único prefixo `aircraft_positions/`, use um job externo (ex.: Athena CTAS /
>   Glue) pós-carga.
> - No target S3 a tabela é gravada como tabela padrão (não particionada).
>   DDL de partição (`ADD`/`DROP`/`TRUNCATE`) não é capturado no CDC.
> - Novas partições criadas depois do start do task só entram na replicação
>   após um reload do task (o DMS enumera as tabelas no início).

### Reiniciar full load + CDC (todas as tabelas)

O target S3 usa `TargetTablePrepMode = TRUNCATE_BEFORE_LOAD`, que apaga os
arquivos existentes do folder da tabela antes do full load (evita duplicados
em reloads). Para reiniciar do zero após alterar os table mappings:

```bash
# 1. Parar a replicação
aws dms stop-replication \
  --replication-config-arn <REPLICATION_CONFIG_ARN>

# 2. Atualizar table mappings / settings no config live
aws dms modify-replication-config \
  --replication-config-arn <REPLICATION_CONFIG_ARN> \
  --table-mappings file://infra/table-mappings.json \
  --replication-settings file://<replication-settings.json>

# 3. Limpar dados stale (prefixo antigo do run anterior)
aws s3 rm s3://<bucket>/dms/flightradar/ --recursive

# 4. Reload completo: full load de todas as tabelas + CDC
aws dms start-replication \
  --replication-config-arn <REPLICATION_CONFIG_ARN> \
  --start-replication-type reload-target
```

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
- Secrets Manager secret com credenciais do Aurora (nome definido via `DB_SECRET_NAME` no `.env`).
  Se o secret **já existir** com esse nome, ele é **reutilizado**; se **não existir**, o deploy o **cria**
  automaticamente com as credenciais do `.env` (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`).
- Bucket S3 de landing zone existente
- VPC com subnets privadas para o DMS Serverless

## Deploy rápido

```bash
# 1. Configure .env
cp .env.example .env
# Preencha DB_SECRET_NAME (nome do secret) e as credenciais do Aurora
# (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD).
# O secret é criado pelo deploy se não existir, ou reutilizado se já existir.

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
