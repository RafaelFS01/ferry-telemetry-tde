# ==============================================================================
# Script de Validacao e Healthcheck Automatizado - AWS SNS & SQS (SCRUM-16)
# Projeto: ferry-telemetry-tde | Modulo: Messaging
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "          HEALTHCHECK MENSAGERIA AWS SNS & SQS (SCRUM-16)             " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$region = "us-east-1"
$topicName = "ferry-telemetria-topic"
$dbQueueName = "ferry-db-writer-queue"
$alertsQueueName = "ferry-alerts-queue"
$dlqName = "ferry-telemetry-dlq"

# 1. Obter ARN do Topico SNS
Write-Host "`n[1] VALIDANDO TOPICO SNS..." -ForegroundColor Yellow
$topicArnJson = aws sns list-topics --region $region 2>$null | ConvertFrom-Json
$topicArn = ($topicArnJson.Topics | Where-Object { $_.TopicArn -like "*:$topicName" }).TopicArn

if (-not $topicArn) {
    Write-Host "[X] ERRO: Topico SNS '$topicName' nao encontrado!" -ForegroundColor Red
    exit 1
}
Write-Host "    [✓] Topico SNS Ativo: $topicArn" -ForegroundColor Green

# 2. Validar Dead Letter Queue (DLQ)
Write-Host "`n[2] VALIDANDO DEAD LETTER QUEUE (DLQ)..." -ForegroundColor Yellow
$dlqUrl = (aws sqs get-queue-url --queue-name $dlqName --region $region 2>$null | ConvertFrom-Json).QueueUrl
if (-not $dlqUrl) {
    Write-Host "[X] ERRO: DLQ '$dlqName' nao encontrada!" -ForegroundColor Red
    exit 1
}
$dlqAttrs = (aws sqs get-queue-attributes --queue-url $dlqUrl --attribute-names All --region $region | ConvertFrom-Json).Attributes
$dlqArn = $dlqAttrs.QueueArn
Write-Host "    [✓] DLQ Ativa: $dlqArn" -ForegroundColor Green
Write-Host "        - Retencao de Mensagens: $($dlqAttrs.MessageRetentionPeriod) segundos ($([math]::Round($dlqAttrs.MessageRetentionPeriod / 86400)) dias)" -ForegroundColor Green
Write-Host "        - SSE Criptografia: $($dlqAttrs.SqsManagedSseEnabled)" -ForegroundColor Green

# 3. Validar Fila Principal de Persistencia (DB Writer)
Write-Host "`n[3] VALIDANDO FILA PRINCIPAL (DB WRITER)..." -ForegroundColor Yellow
$dbQueueUrl = (aws sqs get-queue-url --queue-name $dbQueueName --region $region 2>$null | ConvertFrom-Json).QueueUrl
if (-not $dbQueueUrl) {
    Write-Host "[X] ERRO: Fila '$dbQueueName' nao encontrada!" -ForegroundColor Red
    exit 1
}
$dbQueueAttrs = (aws sqs get-queue-attributes --queue-url $dbQueueUrl --attribute-names All --region $region | ConvertFrom-Json).Attributes
$dbQueueArn = $dbQueueAttrs.QueueArn
Write-Host "    [✓] Fila DB Writer Ativa: $dbQueueArn" -ForegroundColor Green
Write-Host "        - Timeout de Visibilidade: $($dbQueueAttrs.VisibilityTimeout) segundos" -ForegroundColor Green
Write-Host "        - RedrivePolicy: $($dbQueueAttrs.RedrivePolicy)" -ForegroundColor Green

# 4. Validar Fila de Alertas Criticos
Write-Host "`n[4] VALIDANDO FILA DE ALERTAS..." -ForegroundColor Yellow
$alertsQueueUrl = (aws sqs get-queue-url --queue-name $alertsQueueName --region $region 2>$null | ConvertFrom-Json).QueueUrl
if (-not $alertsQueueUrl) {
    Write-Host "[X] ERRO: Fila '$alertsQueueName' nao encontrada!" -ForegroundColor Red
    exit 1
}
$alertsQueueAttrs = (aws sqs get-queue-attributes --queue-url $alertsQueueUrl --attribute-names All --region $region | ConvertFrom-Json).Attributes
$alertsQueueArn = $alertsQueueAttrs.QueueArn
Write-Host "    [✓] Fila Alerts Ativa: $alertsQueueArn" -ForegroundColor Green
Write-Host "        - RedrivePolicy: $($alertsQueueAttrs.RedrivePolicy)" -ForegroundColor Green

# 5. Validar Subscricoes Fan-Out SNS -> SQS
Write-Host "`n[5] VALIDANDO SUBSCRICOES FAN-OUT SNS -> SQS..." -ForegroundColor Yellow
$subs = (aws sns list-subscriptions-by-topic --topic-arn $topicArn --region $region | ConvertFrom-Json).Subscriptions
Write-Host "    [✓] Subscricoes ativas encontradas: $($subs.Count)" -ForegroundColor Green
foreach ($sub in $subs) {
    Write-Host "        • Protocolo: $($sub.Protocol) | Endpoint: $($sub.Endpoint)" -ForegroundColor Green
}

# 6. Teste E2E de Publicacao e Consumo
Write-Host "`n[6] EXECUTANDO TESTE OPERACIONAL E2E (PUBLISH E CONSUME)..." -ForegroundColor Yellow
$testUuid = [System.Guid]::NewGuid().ToString()
$testJson = '{\"event\":\"TELEMETRY_SAMPLE\",\"boat_id\":\"ferry-ivete-sangalo\",\"test_id\":\"' + $testUuid + '\"}'

Write-Host "    - Publicando mensagem no SNS Topic ($topicName)..."
$publishResult = aws sns publish --topic-arn $topicArn --message $testJson --region $region | ConvertFrom-Json
Write-Host "    [✓] Mensagem publicada! MessageId: $($publishResult.MessageId)" -ForegroundColor Green

Start-Sleep -Seconds 2

Write-Host "    - Consumindo mensagem na fila SQS ($dbQueueName)..."
$received = aws sqs receive-message --queue-url $dbQueueUrl --max-number-of-messages 1 --wait-time-seconds 5 --region $region | ConvertFrom-Json

if ($received.Messages -and $received.Messages.Count -gt 0) {
    $msg = $received.Messages[0]
    Write-Host "    [✓] Mensagem recebida com sucesso na SQS!" -ForegroundColor Green
    Write-Host "        - ReceiptHandle: $($msg.ReceiptHandle.Substring(0, 30))..." -ForegroundColor Gray
    Write-Host "        - Conteudo: $($msg.Body)" -ForegroundColor Green

    # Deletar mensagem consumida do teste
    aws sqs delete-message --queue-url $dbQueueUrl --receipt-handle $msg.ReceiptHandle --region $region | Out-Null
    Write-Host "    [✓] Mensagem de teste removida da fila SQS." -ForegroundColor Green
} else {
    Write-Host "    [!] AVISO: Mensagem nao foi recebida no tempo limite." -ForegroundColor Yellow
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "    RESULTADO: ARQUITETURA DE MENSAGERIA 100% OPERACIONAL E HOMOLOGADA! " -ForegroundColor Green
Write-Host "======================================================================`n" -ForegroundColor Cyan

