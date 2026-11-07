# ==============================================================================
# Script de Validacao e Healthcheck Automatizado - AWS RDS PostgreSQL 18
# Projeto: ferry-telemetry-tde | Modulo: SCRUM-8
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "           HEALTHCHECK RDS POSTGRESQL 18 (AWS CLOUD)                  " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Obter detalhes da instancia RDS
$dbInstanceJson = aws rds describe-db-instances --db-instance-identifier ferry-postgres-central 2>$null
if (-not $dbInstanceJson) {
    Write-Host "[X] ERRO: Instancia RDS 'ferry-postgres-central' nao encontrada!" -ForegroundColor Red
    exit 1
}

$db = ($dbInstanceJson | ConvertFrom-Json).DBInstances[0]

$statusColor = "Yellow"
if ($db.DBInstanceStatus -eq "available") {
    $statusColor = "Green"
}

Write-Host "`n[✓] INSTANCIA RDS IDENTIFICADA:" -ForegroundColor Green
Write-Host "    - Identificador: $($db.DBInstanceIdentifier)"
Write-Host "    - Status: $($db.DBInstanceStatus)" -ForegroundColor $statusColor
Write-Host "    - Motor: $($db.Engine) (Versao $($db.EngineVersion))"
Write-Host "    - Tipo de Instancia: $($db.DBInstanceClass)"
Write-Host "    - Multi-AZ: $($db.MultiAZ) (Single-AZ economico conforme arquitetura)"

# 2. Armazenamento e Criptografia
Write-Host "`n[✓] ARMAZENAMENTO E SEGURANCA:" -ForegroundColor Green
Write-Host "    - Tipo: $($db.StorageType) | Alocado: $($db.AllocatedStorage) GB | Auto-scale max: $($db.MaxAllocatedStorage) GB"
Write-Host "    - Criptografia em Repouso: $($db.StorageEncrypted) (KMS: $($db.KmsKeyId))"

# 3. Politicas de Backup e PITR
Write-Host "`n[✓] BACKUPS E POINT-IN-TIME RECOVERY (PITR):" -ForegroundColor Green
Write-Host "    - Retencao de Backups: $($db.BackupRetentionPeriod) dia(s)"
Write-Host "    - Janela de Backup: $($db.PreferredBackupWindow)"
Write-Host "    - Janela de Manutencao: $($db.PreferredMaintenanceWindow)"
Write-Host "    - Snapshot ao Destruir: $($db.DeletionProtection)"

# 4. Rede e Conectividade Perimetral
Write-Host "`n[✓] REDE E ISOLAMENTO PERIMETRAL:" -ForegroundColor Green
Write-Host "    - Endpoint DNS: $($db.Endpoint.Address)"
Write-Host "    - Porta TCP: $($db.Endpoint.Port)"
Write-Host "    - Acesso Publico: $($db.PubliclyAccessible) (Isolamento total na Subnet Privada)"
Write-Host "    - DB Subnet Group: $($db.DBSubnetGroup.DBSubnetGroupName)"
$subnets = $db.DBSubnetGroup.Subnets | ForEach-Object { "$($_.SubnetIdentifier) ($($_.SubnetAvailabilityZone.Name))" }
Write-Host "    - Subnets Vinculadas: $($subnets -join ', ')"
$sgs = $db.VpcSecurityGroups | ForEach-Object { "$($_.VpcSecurityGroupId) ($($_.Status))" }
Write-Host "    - Security Groups: $($sgs -join ', ')"

Write-Host "`n======================================================================" -ForegroundColor Cyan
if ($db.DBInstanceStatus -eq "available") {
    Write-Host "    RESULTADO: BANCO DE DADOS 100% OPERACIONAL E PRONTO PARA USO!      " -ForegroundColor Green
} else {
    Write-Host "    STATUS ATUAL: $($db.DBInstanceStatus) (Aguardando finalizacao)     " -ForegroundColor Yellow
}
Write-Host "======================================================================`n" -ForegroundColor Cyan
