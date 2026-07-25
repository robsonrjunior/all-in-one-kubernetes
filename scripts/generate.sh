#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GENERATED_DIR="$PROJECT_ROOT/kubernetes/generated"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

echo "=== Gerando manifestos Kubernetes a partir do .env ==="

if [ ! -f "$ENV_FILE" ]; then
  echo ""
  echo "ERRO: Arquivo .env nao encontrado em $PROJECT_ROOT"
  echo ""
  echo "Para criar o arquivo .env:"
  echo "  cp .env.example .env"
  echo "  # Edite .env com os valores do seu ambiente"
  echo ""
  exit 1
fi

echo ">>> Lendo variaveis do .env..."
set -a
source "$ENV_FILE"
set +a

TARGET_ENV="${1:-}"

if [ -n "$TARGET_ENV" ]; then
  if [ "$TARGET_ENV" != "dev" ] && [ "$TARGET_ENV" != "homolog" ] && [ "$TARGET_ENV" != "prod" ]; then
    echo "ERRO: Ambiente invalido '$TARGET_ENV'. Use: dev, homolog ou prod."
    exit 1
  fi
fi

# Deriva entrypoint do Ingress baseado em TLS_ENABLED
if [ "${TLS_ENABLED:-false}" = "true" ]; then
  export INGRESS_ENTRYPOINT="websecure"
  export N8N_PROTOCOL="https"
  export N8N_SECURE_COOKIE='"true"'
else
  export INGRESS_ENTRYPOINT="web"
  export N8N_PROTOCOL="http"
  export N8N_SECURE_COOKIE='"false"'
fi

# Valida que INGRESS_ENTRYPOINT esta definida
if [ -z "${INGRESS_ENTRYPOINT:-}" ]; then
  echo "ERRO: INGRESS_ENTRYPOINT nao foi definida. Verifique TLS_ENABLED no .env."
  exit 1
fi

echo ">>> TLS_ENABLED=${TLS_ENABLED:-false} -> INGRESS_ENTRYPOINT=$INGRESS_ENTRYPOINT, N8N_PROTOCOL=$N8N_PROTOCOL"

generate_env() {
  local env="$1"
  echo ">>> Gerando overlay $env..."
  kubectl kustomize "$PROJECT_ROOT/kubernetes/overlays/$env/" | sed 's/\$uri\b/__NGINX_URI__/g' | envsubst | sed 's/__NGINX_URI__/$uri/g' | sed -E 's/^(\s+[A-Z0-9_]+): ([0-9]+)$/\1: "\2"/' > "$GENERATED_DIR/$env.yaml"
}

mkdir -p "$GENERATED_DIR"

if [ -n "$TARGET_ENV" ]; then
  generate_env "$TARGET_ENV"
else
  generate_env "dev"
  generate_env "homolog"
  generate_env "prod"
fi

echo ""
echo ">>> Manifestos gerados em $GENERATED_DIR/"
ls -la "$GENERATED_DIR/"
echo ""
echo ">>> Pronto! Use 'make deploy' para aplicar."
