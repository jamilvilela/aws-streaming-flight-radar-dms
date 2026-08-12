#!/bin/bash
# setup-env.sh - Load environment variables, deploy Terraform for
# DMS Serverless (Aurora PostgreSQL → S3 Parquet), then verify
# every resource and dump connection info.
#
# Usage:   ./setup-env.sh
# Aliases: ./setup-env.sh --skip-apply   # init/validate/plan only
#          ./setup-env.sh --no-verify    # skip post-deploy checks
#
# Exit codes:
#   0  success
#   1  prerequisites missing (env, tfvars, credentials)
#   2  terraform step failed
#   3  post-deploy verification found missing resources

set -a  # export everything we `source`

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------
SKIP_APPLY=0
NO_VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --skip-apply) SKIP_APPLY=1 ;;
    --no-verify)  NO_VERIFY=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
section() { echo -e "\n${BOLD}${BLUE}== $* ==${NC}"; }
ok()      { echo -e "  ${GREEN}✅ $*${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $*${NC}"; }
fail()    { echo -e "  ${RED}❌ $*${NC}"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "Comando obrigatório ausente: $1"; exit 1; }
}

# ---------------------------------------------------------------------------
# STEP 1: Load .env
# ---------------------------------------------------------------------------
section "STEP 1 — Carregando .env"

if [ ! -f .env ]; then
  fail "Arquivo .env não encontrado na raiz do projeto."
  echo "   Copie .env.example para .env e preencha com seus valores"
  echo "   cp .env.example .env"
  exit 1
fi
source .env
ok "Variáveis de .env carregadas"

if [ -n "$AWS_REGION" ]; then
  export TF_VAR_aws_region="$AWS_REGION"
fi

# ── VPC, subnets e Aurora são descobertos via Terraform data sources ─────
# Não é mais necessário exportar TF_VAR_* para esses valores.
# O Terraform descobre automaticamente:
#   - VPC pelo tag Name (var.vpc_name ou "${var.project_name}-vpc")
#   - Subnets da VPC
#   - Aurora cluster endpoint/port/db_name/SG pelo cluster_identifier

# ---------------------------------------------------------------------------
# STEP 2: AWS credentials sanity check (warn only, do not block)
# ---------------------------------------------------------------------------
section "STEP 2 — Verificando credenciais AWS"

CREDENTIALS_FOUND=0

# Check 1: environment variables
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  CREDENTIALS_FOUND=1
  ok "Credenciais AWS via environment variables"
fi

# Check 2: aws configure (default profile)
if [ "$CREDENTIALS_FOUND" -eq 0 ] && [ -f "$HOME/.aws/credentials" ]; then
  if grep -q "aws_access_key_id" "$HOME/.aws/credentials" 2>/dev/null; then
    CREDENTIALS_FOUND=1
    ok "Credenciais AWS via aws configure (default profile)"
  fi
fi

# Check 3: try sts get-caller-identity (covers SSO, instance profile, etc.)
if [ "$CREDENTIALS_FOUND" -eq 0 ]; then
  if aws sts get-caller-identity &>/dev/null; then
    CREDENTIALS_FOUND=1
    ok "Credenciais AWS ativas (SSO / instance profile / environment)"
  fi
fi

if [ "$CREDENTIALS_FOUND" -eq 0 ]; then
  warn "Nenhuma credencial AWS encontrada."
  echo "   Configure com 'aws configure', exporte AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY,"
  echo "   ou use uma role/SSO via 'aws sso login'."
  echo "   Continuando (pode falhar no terraform apply se não houver credenciais)."
fi

# ---------------------------------------------------------------------------
# STEP 3: Move into infra/
# ---------------------------------------------------------------------------
section "STEP 3 — Acessando diretório infra"

if [ ! -d "infra" ]; then
  fail "Diretório infra/ não encontrado. Execute este script da raiz do projeto."
  exit 1
fi
cd infra || exit 1
ok "Diretório atual: $(pwd)"

set +a  # done auto-exporting

TFVARS_FILE="tfvars/terraform.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
  fail "Arquivo de variáveis '$TFVARS_FILE' não encontrado."
  echo "   Crie a partir do template: cp tfvars/terraform.tfvars.example tfvars/terraform.tfvars"
  exit 1
fi

# ---------------------------------------------------------------------------
# STEP 4-7: Terraform init/validate/plan/apply
# ---------------------------------------------------------------------------
section "STEP 4 — terraform init"
terraform init
[ $? -ne 0 ] && { fail "terraform init falhou"; exit 2; }
ok "init concluído"

section "STEP 5 — terraform validate"
terraform validate
[ $? -ne 0 ] && { fail "terraform validate falhou"; exit 2; }
ok "validate concluído"

section "STEP 6 — terraform plan"
terraform plan -var-file="$TFVARS_FILE" -out=tfplan
[ $? -ne 0 ] && { fail "terraform plan falhou"; exit 2; }
ok "plan concluido (salvo em tfplan)"

if [ "$SKIP_APPLY" -eq 1 ]; then
  warn "--skip-apply informado; apply nao sera executado."
else
  # -------------------------------------------------------------------------
  # STEP 6.5 — Verifica o secret existente do DMS (não cria nem sobrescreve)
  # O secret é gerenciado externamente (nome definido via DB_SECRET_NAME no .env)
  # e deve existir antes do apply — o Terraform lê via data source.
  # -------------------------------------------------------------------------
  PROJECT_NAME="${PROJECT_NAME:-${TF_VAR_project_name:-$(grep -E '^project_name' "$TFVARS_FILE" | head -1 | cut -d= -f2 | tr -d ' \"')}}"
  PROJECT_NAME="${PROJECT_NAME//$'\r'}"
  # Nome do secret vem do .env (DB_SECRET_NAME) — não é versionado no tfvars.
  DMS_SECRET_NAME="${DB_SECRET_NAME:-${PROJECT_NAME}/aurora-credentials}"
  export TF_VAR_db_secret_name="$DMS_SECRET_NAME"

  if aws secretsmanager describe-secret --secret-id "$DMS_SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
    ok "Secret existente $DMS_SECRET_NAME encontrado (será utilizado pelo DMS)"
  else
    warn "Secret $DMS_SECRET_NAME não encontrado."
    echo "   O setup-env não cria secrets — verifique/crie o secret existente antes do apply:"
    echo "   aws secretsmanager describe-secret --secret-id \"$DMS_SECRET_NAME\" --region \"$AWS_REGION\""
  fi

  section "STEP 7 — terraform apply"
  terraform apply -var-file="$TFVARS_FILE" -auto-approve tfplan
  [ $? -ne 0 ] && { fail "terraform apply falhou"; exit 2; }
  ok "apply concluido"

  # ── Secret do DMS: utilizado como está (não é criado nem sobrescrito) ──
  # O secret existente já contém as credenciais do Aurora (username, password,
  # host, port, dbname). O setup-env não altera o secret.
  ok "Secret '$DMS_SECRET_NAME' será utilizado como está pelo source endpoint do DMS"

fi

# ---------------------------------------------------------------------------
# STEP 8: Show all Terraform outputs
# ---------------------------------------------------------------------------
section "STEP 8 — Outputs do Terraform"

require_cmd terraform

# Helper: print a single output, falling back to a placeholder when missing.
print_output() {
  local name="$1"
  local sensitive="${2:-false}"

  # Try -raw first (simple string outputs)
  local value
  if value="$(terraform output -raw "$name" 2>/dev/null)" && [ -n "$value" ]; then
    if [ "$sensitive" = "true" ]; then
      echo -e "  ${BOLD}${name}${NC} = ${YELLOW}${value}${NC} ${RED}(sensitive)${NC}"
    else
      echo -e "  ${BOLD}${name}${NC} = ${value}"
    fi
    return
  fi

  # Fallback to -json for complex outputs (maps, lists, objects)
  if value="$(terraform output -json "$name" 2>/dev/null)" && [ -n "$value" ] && [ "$value" != "null" ]; then
    if command -v jq &>/dev/null; then
      echo -e "  ${BOLD}${name}${NC} ="
      echo "$value" | jq -r 'to_entries[] | "    \(.key): \(.value | tostring)"' 2>/dev/null || \
      echo "$value" | jq -r '. | tostring' 2>/dev/null || \
      echo "$value"
    else
      echo -e "  ${BOLD}${name}${NC} = ${value}"
    fi
    return
  fi

  warn "Output '${name}' ausente"
}

echo -e "  ${BLUE}-- DMS Serverless --${NC}"
print_output dms_replication_config_id
print_output dms_replication_config_arn
print_output dms_source_endpoint_arn
print_output dms_target_endpoint_arn
print_output dms_replication_config_identifier
print_output dms_security_group_id

# ---------------------------------------------------------------------------
# STEP 9: Post-deploy verification
# ---------------------------------------------------------------------------
if [ "$NO_VERIFY" -eq 1 ]; then
  warn "--no-verify informado; pulando checagens pós-deploy."
  exit 0
fi

section "STEP 9 — Verificação pós-deployment"

require_cmd aws
require_cmd jq

REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${TF_VAR_project_name:-$(grep -E '^project_name' "$TFVARS_FILE" | head -1 | cut -d= -f2 | tr -d ' \"')}"
PROJECT_NAME="${PROJECT_NAME//$'\r'}"
if [ -z "$PROJECT_NAME" ]; then
  fail "Não foi possível determinar project_name; defina TF_VAR_project_name ou edite o tfvars"
  exit 3
fi
ok "Projeto detectado: $PROJECT_NAME (region: $REGION)"

# ---------------------------------------------------------------------------
# 9.1 DMS Serverless
# ---------------------------------------------------------------------------
section "9.1 — DMS Serverless"
DMS_CONFIGS=$(aws dms describe-replication-configs --region "$REGION" \
  --query "ReplicationConfigs[?contains(ReplicationConfigIdentifier, \`${PROJECT_NAME}\`)].{ID:ReplicationConfigIdentifier,Status:Status}" \
  --output json 2>/dev/null || echo "[]")
DMS_CONFIG_COUNT=$(echo "$DMS_CONFIGS" | jq 'length')
if [ "$DMS_CONFIG_COUNT" -gt 0 ]; then
  ok "$DMS_CONFIG_COUNT DMS Serverless config(s):"
  echo "$DMS_CONFIGS" | jq -r '.[] | "   - \(.ID) (status: \(.Status))"'
else
  warn "Nenhuma DMS Serverless config do projeto encontrada"
fi

# ---------------------------------------------------------------------------
# 9.3 KMS keys
# ---------------------------------------------------------------------------
section "9.2 — KMS Keys"
KMS_KEYS=$(aws kms list-aliases --region "$REGION" \
  --query 'Aliases[?contains(AliasName, `'"$PROJECT_NAME"'`)].AliasName' \
  --output json 2>/dev/null || echo "[]")
KMS_COUNT=$(echo "$KMS_KEYS" | jq 'length')
if [ "$KMS_COUNT" -gt 0 ]; then
  ok "$KMS_COUNT KMS alias(es):"
  echo "$KMS_KEYS" | jq -r '.[] | "   - " + .'
else
  warn "Nenhum alias KMS do projeto encontrado (pode ser intencional)"
fi

# ---------------------------------------------------------------------------
# STEP 10: Final summary
# ---------------------------------------------------------------------------
section "STEP 10 — Resumo final"

DMS_CONFIG_ID=$(terraform output -raw dms_replication_config_identifier 2>/dev/null || echo "<missing>")
DMS_SOURCE_ARN=$(terraform output -raw dms_source_endpoint_arn 2>/dev/null || echo "<missing>")
DMS_TARGET_ARN=$(terraform output -raw dms_target_endpoint_arn 2>/dev/null || echo "<missing>")

echo ""
echo -e "${BOLD}🔗 Recursos DMS implantados:${NC}"
echo -e "  ${BOLD}Replication Config${NC}  = ${GREEN}${DMS_CONFIG_ID}${NC}"
echo -e "  ${BOLD}Source Endpoint${NC}     = ${GREEN}${DMS_SOURCE_ARN}${NC}"
echo -e "  ${BOLD}Target Endpoint${NC}     = ${GREEN}${DMS_TARGET_ARN}${NC}"
echo ""
echo -e "O cluster Aurora PostgreSQL é gerenciado externamente."
echo -e "Certifique-se de que o Secret ${CYAN}${DMS_SECRET_NAME:-${PROJECT_NAME}/aurora-credentials}${NC}"
echo -e "no AWS Secrets Manager contenha as credenciais corretas do Aurora."
echo ""

if [ "${MISSING:-0}" = "1" ]; then
  fail "Verificação pós-deployment encontrou recursos faltando (ver acima)."
  exit 3
fi

echo -e "${GREEN}${BOLD}🎉 Deployment concluído e verificado com sucesso!${NC}"
exit 0
