# ==============================================================================
# Script de Validacao e Healthcheck - AWS ECS Fargate & ALB gRPC (SCRUM-18)
# Projeto: ferry-telemetry-tde | Modulo: Compute & Load Balancing
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     HEALTHCHECK TERRAFORM: ECS FARGATE & ALB L7 gRPC (SCRUM-18)      " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$region = "us-east-1"
$clusterName = "ferry-cluster-prod"
$albName = "ferry-alb-prod"
$ingestionTaskFamily = "ferry-central-ingestion-prod"
$workerTaskFamily = "ferry-central-worker-prod"

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

# 3. Verificacao Opcional de Infraestrutura Ativa (caso provisionada na AWS)
Write-Host "`n[3] VERIFICANDO DISPONIBILIDADE NA AWS (SE ATIVA)..." -ForegroundColor Yellow

$clusterJson = aws ecs describe-clusters --clusters $clusterName --region $region 2>$null | ConvertFrom-Json
if ($clusterJson -and $clusterJson.clusters.Count -gt 0 -and $clusterJson.clusters[0].status -eq "ACTIVE") {
    Write-Host "    [✓] Cluster ECS Fargate Ativo: $($clusterJson.clusters[0].clusterArn)" -ForegroundColor Green
    Write-Host "        - Capacity Providers: $($clusterJson.clusters[0].capacityProviders -join ', ')" -ForegroundColor Green
} else {
    Write-Host "    [i] Cluster ECS '$clusterName' nao ativo no momento (ambiente destruido ou sob demanda)." -ForegroundColor DarkGray
}

$albJson = aws elbv2 describe-load-balancers --names $albName --region $region 2>$null | ConvertFrom-Json
if ($albJson -and $albJson.LoadBalancers.Count -gt 0) {
    Write-Host "    [✓] ALB L7 Ativo: $($albJson.LoadBalancers[0].DNSName)" -ForegroundColor Green
    Write-Host "        - Esquema: $($albJson.LoadBalancers[0].Scheme) | Estado: $($albJson.LoadBalancers[0].State.Code)" -ForegroundColor Green
} else {
    Write-Host "    [i] ALB '$albName' nao ativo no momento (ambiente destruido ou sob demanda)." -ForegroundColor DarkGray
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host " [✓] HOMOLOGACAO DO MODULO SCRUM-18 (ECS FARGATE & ALB) CONCLUIDA COM SUCESSO!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
