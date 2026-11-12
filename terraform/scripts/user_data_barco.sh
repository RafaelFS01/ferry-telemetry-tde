#!/bin/bash
# ==============================================================================
# Script de Provisionamento Inicial (User Data) - Nó Barco (Edge Simulator)
# Projeto: ferry-telemetry-tde | Módulo: Edge Computing (SCRUM-19)
# Sistema Operacional: Ubuntu 24.04 LTS Noble Numbat (x86_64)
# ==============================================================================

set -euo pipefail

LOG_FILE="/var/log/user-data.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] === INICIANDO PROVISIONAMENTO DO NO BARCO (SCRUM-19) ==="

export DEBIAN_FRONTEND=noninteractive

# 1. Atualizacao dos pacotes base
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [1/6] Atualizando pacotes do sistema..."
apt-get update -y
apt-get upgrade -y

# 2. Instalacao de utilitarios essenciais e Chrony (Amazon Time Sync)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [2/6] Instalando dependencias basicas e Chrony..."
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  build-essential \
  jq \
  htop \
  chrony

# Configuracao do Chrony com o Amazon Time Sync Service (169.254.169.123)
if ! grep -q "169.254.169.123" /etc/chrony/chrony.conf; then
  echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony/chrony.conf
  systemctl restart chrony
fi

# 3. Instalacao do Docker Engine e Docker Compose Plugin
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [3/6] Instalando Docker Engine e Docker Compose..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# 4. Instalacao do Node.js 24 LTS via NodeSource
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [4/6] Instalando Node.js 24 LTS..."
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs

# 5. Criacao da estrutura de diretorios para a aplicacao
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [5/6] Preparando diretorio da aplicacao /opt/ferry-boat..."
mkdir -p /opt/ferry-boat
chown -R ubuntu:ubuntu /opt/ferry-boat

# 6. Validacao das versoes instaladas
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [6/6] Verificando instalacoes..."
echo "  - Docker: $(docker --version)"
echo "  - Docker Compose: $(docker compose version)"
echo "  - Node.js: $(node --version)"
echo "  - NPM: $(npm --version)"
echo "  - Chrony: $(chronyc tracking | grep 'Reference ID' || true)"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] === PROVISIONAMENTO DO NO BARCO FINALIZADO COM SUCESSO ==="

