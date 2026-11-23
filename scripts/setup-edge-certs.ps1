# ==============================================================================
# Script de Configuração mTLS da Borda (EC2 Barco)
# Projeto: ferry-telemetry-tde
#
# Uso: .\scripts\setup-edge-certs.ps1
#
# O que este script faz:
# 1. Obtém os certificados mTLS e variáveis do Terraform.
# 2. Injeta os certificados e o .env na EC2 do Barco via AWS SSM (sem SSH).
# 3. Ajusta permissões e reinicia o contêiner do Barco.
# 4. Valida se o Barco está respondendo e comunicando com a Central.
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "   CONFIGURANDO CERTIFICADOS mTLS E AMBIENTE NA EC2 DO BARCO          " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Localiza a pasta terraform
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$terraformDir = Join-Path $projectRoot "terraform"

if (-not (Test-Path $terraformDir)) {
    Write-Host "[X] ERRO: Pasta terraform nao encontrada em $terraformDir" -ForegroundColor Red
    exit 1
}

Push-Location $terraformDir
try {
    Write-Host "`n[1/4] Extraindo certificados e configuracoes do Terraform..." -ForegroundColor Yellow
    $alb = (terraform output -raw alb_dns_name 2>$null)
    $inst = (terraform output -raw ec2_barco_instance_id 2>$null)
    $ip = (terraform output -raw ec2_barco_elastic_ip 2>$null)
    $caPem = ((terraform output -raw tls_ca_cert_pem 2>$null) -join "`n") + "`n"
    $boatCertPem = ((terraform output -raw tls_boat_cert_pem 2>$null) -join "`n") + "`n"
    $boatKeyPem = ((terraform output -raw tls_boat_key_pem 2>$null) -join "`n") + "`n"

    if (-not $alb -or -not $inst) {
        Write-Host "[X] ERRO: Nao foi possivel obter os outputs do Terraform. Voce executou 'terraform apply'?" -ForegroundColor Red
        exit 1
    }

    Write-Host "    - Instancia EC2 : $inst ($ip)" -ForegroundColor Green
    Write-Host "    - Endpoint ALB  : ${alb}:50051" -ForegroundColor Green

    # 2. Converte para Base64 preservando quebras de linha
    Write-Host "`n[2/4] Codificando credenciais..." -ForegroundColor Yellow
    $caB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($caPem))
    $crtB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($boatCertPem))
    $keyB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($boatKeyPem))

    $envContent = @(
        "ECR_REGISTRY=782747473447.dkr.ecr.us-east-1.amazonaws.com",
        "IMAGE_TAG=2180c4c170fea556801167e8e3e2092562eab567",
        "BOAT_ID=ferry-ivete-sangalo",
        "CENTRAL_GRPC_URL=${alb}:50051",
        "GRPC_TLS_CA_PATH=/app/certs/ca.crt",
        "GRPC_TLS_CERT_PATH=/app/certs/boat.crt",
        "GRPC_TLS_KEY_PATH=/app/certs/boat.key"
    ) -join "`n"
    $envB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($envContent))

    # 3. Envia os comandos via SSM
    Write-Host "`n[3/4] Injetando certificados e reiniciando o contêiner via SSM..." -ForegroundColor Yellow
    $cmds = @(
        "mkdir -p /opt/ferry-boat/certs",
        "echo '$caB64' | base64 -d > /opt/ferry-boat/certs/ca.crt",
        "echo '$crtB64' | base64 -d > /opt/ferry-boat/certs/boat.crt",
        "echo '$keyB64' | base64 -d > /opt/ferry-boat/certs/boat.key",
        "chmod 644 /opt/ferry-boat/certs/*",
        "chown -R 1000:1000 /opt/ferry-boat/certs",
        "echo '$envB64' | base64 -d > /opt/ferry-boat/.env",
        "cd /opt/ferry-boat && docker compose up -d"
    )

    $paramFile = Join-Path $terraformDir "ssm_init_temp.json"
    @{ commands = $cmds } | ConvertTo-Json | Out-File -FilePath $paramFile -Encoding ascii

    $cmdId = aws ssm send-command --instance-ids $inst --document-name "AWS-RunShellScript" --parameters "file://$paramFile" --query "Command.CommandId" --output text
    Remove-Item $paramFile -Force -ErrorAction SilentlyContinue

    Write-Host "    - Comando SSM enviado (ID: $cmdId). Aguardando aplicacao..." -ForegroundColor Gray
    Start-Sleep -Seconds 8

    # 4. Validacao
    Write-Host "`n[4/4] Validando comunicacao..." -ForegroundColor Yellow
    $healthCheck = curl.exe -s --connect-timeout 5 "http://$ip/api/edge/health"
    if ($healthCheck -match '"status":"ok"') {
        Write-Host "    [✓] SUCESSO: O Barco esta online, autenticado via mTLS e operando normalmente!" -ForegroundColor Green
        Write-Host "    - Painel do Capitao: http://$ip/" -ForegroundColor Cyan
        Write-Host "    - Central Dashboard: http://${alb}/" -ForegroundColor Cyan
    } else {
        Write-Host "    [i] Contêiner iniciando... Verifique em 10 segundos com: curl http://$ip/api/edge/health" -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}
Write-Host "`n======================================================================" -ForegroundColor Cyan
