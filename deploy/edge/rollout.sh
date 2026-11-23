#!/usr/bin/env bash
# Executado na EC2 do Nó Barco via SSM (AWS-RunShellScript) pelo cd-edge-deploy.yml.
# Entradas (variáveis de ambiente):
#   ECR_REGISTRY   registro ECR de onde as imagens são baixadas
#   IMAGE_TAG      SHA do commit publicado
#   COMPOSE_B64    deploy/edge/docker-compose.yml codificado em base64
set -euo pipefail
: "${ECR_REGISTRY:?}" "${IMAGE_TAG:?}" "${COMPOSE_B64:?}"

APP_DIR=/opt/ferry-boat

# O pull autentica com o perfil da instância, sem docker login nem senha em disco
if ! command -v docker-credential-ecr-login >/dev/null; then
  # Aguarda cloud-init/apt concluir no primeiro boot da EC2
  cloud-init status --wait || true
  if ! command -v docker-credential-ecr-login >/dev/null; then
    apt-get update -y
    apt-get install -y amazon-ecr-credential-helper
  fi
fi
mkdir -p /root/.docker "$APP_DIR/certs"
printf '{"credHelpers":{"%s":"ecr-login"}}\n' "$ECR_REGISTRY" > /root/.docker/config.json

echo "$COMPOSE_B64" | base64 -d > "$APP_DIR/docker-compose.yml"
cd "$APP_DIR"
export ECR_REGISTRY IMAGE_TAG

docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
docker compose ps
