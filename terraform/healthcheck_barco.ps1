# ==============================================================================
# Script de Validacao e Healthcheck - AWS EC2 Simuladora do Barco (SCRUM-19)
# Projeto: ferry-telemetry-tde | Modulo: Edge Computing
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "       HEALTHCHECK TERRAFORM: EC2 SIMULADORA DO BARCO (SCRUM-19)      " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$region = "us-east-1"
$instanceName = "ferry-barco-simulator-prod"

# 1. Validacao Estatica Terraform
Write-Host "`n[1] VALIDANDO FORMATACAO E SINTAXE DO TERRAFORM..." -ForegroundColor Yellow
$fmtResult = terraform fmt -check
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] ERRO: Formatacao incorreta nos arquivos Terraform!" -ForegroundColor Red
    exit 1
}
Write-Host "    [✓] Formatacao Terraform aprovada." -ForegroundColor Green

$validateResult = terraform validate -json | ConvertFrom-Json
if (-not $validateResult.valid) {
    Write-Host "[X] ERRO: Validacao de sintaxe Terraform falhou!" -ForegroundColor Red
    $validateResult.diagnostics | ForEach-Object { Write-Host "    - $($_.summary): $($_.detail)" -ForegroundColor Red }
    exit 1
}
Write-Host "    [✓] Sintaxe e integridade Terraform aprovadas com sucesso." -ForegroundColor Green

# 2. Verificacao de Recursos no Plano Terraform
Write-Host "`n[2] VERIFICANDO SINTESE DO PLANO DE EXECUCAO..." -ForegroundColor Yellow
$planOutput = terraform plan -no-color 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] ERRO: Falha ao gerar o plano de execucao Terraform!" -ForegroundColor Red
    Write-Host $planOutput
    exit 1
}
Write-Host "    [✓] Plano Terraform gerado com sucesso sem conflitos estruturais." -ForegroundColor Green

# 3. Verificacao de Existencia do Script de User Data
Write-Host "`n[3] VERIFICANDO SCRIPT DE PROVISIONAMENTO USER DATA..." -ForegroundColor Yellow
$userDataPath = "scripts/user_data_barco.sh"
if (-not (Test-Path $userDataPath)) {
    Write-Host "[X] ERRO: Arquivo $userDataPath nao encontrado!" -ForegroundColor Red
    exit 1
}

$userDataContent = Get-Content $userDataPath -Raw
$hasDocker = $userDataContent -match "docker-ce"
$hasNode24 = $userDataContent -match "setup_24.x"
$hasChrony = $userDataContent -match "chrony"

if ($hasDocker -and $hasNode24 -and $hasChrony) {
    Write-Host "    [✓] Script User Data integro: Docker, Node.js 24 LTS e Chrony configurados." -ForegroundColor Green
} else {
    Write-Host "[X] AVISO: Script User Data ausente de componentes essenciais!" -ForegroundColor Red
    exit 1
}

# 4. Verificacao de Infraestrutura Ativa na AWS
Write-Host "`n[4] VERIFICANDO DISPONIBILIDADE NA AWS..." -ForegroundColor Yellow

$instanceJson = aws ec2 describe-instances --filters "Name=tag:Name,Values=$instanceName" "Name=instance-state-name,Values=running,pending,stopped" --region $region 2>$null | ConvertFrom-Json
if ($instanceJson -and $instanceJson.Reservations.Count -gt 0 -and $instanceJson.Reservations[0].Instances.Count -gt 0) {
    $inst = $instanceJson.Reservations[0].Instances[0]
    Write-Host "    [✓] Instancia EC2 Barco Localizada: $($inst.InstanceId) ($($inst.State.Name))" -ForegroundColor Green
    Write-Host "        - Tipo: $($inst.InstanceType) | IP Publico: $($inst.PublicIpAddress) | IP Privado: $($inst.PrivateIpAddress)" -ForegroundColor Green
} else {
    Write-Host "    [i] Instancia EC2 '$instanceName' nao ativa no momento (ambiente destruido ou sob demanda)." -ForegroundColor DarkGray
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host " [✓] HOMOLOGACAO DO MODULO SCRUM-19 (EC2 SIMULADORA) CONCLUIDA COM SUCESSO!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
