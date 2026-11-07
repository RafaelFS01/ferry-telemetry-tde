#!/bin/bash
# Provisiona a mensageria local no LocalStack (executado em /etc/localstack/init/ready.d).
# Espelha o desenho de produção: tópico SNS com fan-out para duas filas SQS,
# cada uma com sua DLQ (3 tentativas, retenção de 14 dias).
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TOPIC_NAME="ferry-telemetria-topic"
QUEUES=("ferry-db-writer-queue" "ferry-alerts-queue")
MAX_RECEIVE_COUNT=3
DLQ_RETENTION_SECONDS=1209600 # 14 dias

echo "[init-localstack] Criando tópico SNS ${TOPIC_NAME}..."
TOPIC_ARN=$(awslocal sns create-topic --name "${TOPIC_NAME}" --region "${REGION}" \
  --query TopicArn --output text)

queue_arn() {
  awslocal sqs get-queue-attributes --queue-url "$1" --region "${REGION}" \
    --attribute-names QueueArn --query Attributes.QueueArn --output text
}

for QUEUE in "${QUEUES[@]}"; do
  DLQ="${QUEUE}-dlq"

  echo "[init-localstack] Criando DLQ ${DLQ}..."
  DLQ_URL=$(awslocal sqs create-queue --queue-name "${DLQ}" --region "${REGION}" \
    --attributes "MessageRetentionPeriod=${DLQ_RETENTION_SECONDS}" \
    --query QueueUrl --output text)
  DLQ_ARN=$(queue_arn "${DLQ_URL}")

  echo "[init-localstack] Criando fila ${QUEUE} com redrive para a DLQ..."
  # RedrivePolicy é um JSON serializado como string dentro do JSON de atributos
  ATTRIBUTES=$(printf '{"RedrivePolicy":"{\\"deadLetterTargetArn\\":\\"%s\\",\\"maxReceiveCount\\":\\"%s\\"}"}' \
    "${DLQ_ARN}" "${MAX_RECEIVE_COUNT}")
  QUEUE_URL=$(awslocal sqs create-queue --queue-name "${QUEUE}" --region "${REGION}" \
    --attributes "${ATTRIBUTES}" \
    --query QueueUrl --output text)
  QUEUE_ARN=$(queue_arn "${QUEUE_URL}")

  echo "[init-localstack] Inscrevendo ${QUEUE} no tópico..."
  awslocal sns subscribe --region "${REGION}" \
    --topic-arn "${TOPIC_ARN}" \
    --protocol sqs \
    --notification-endpoint "${QUEUE_ARN}" \
    --attributes RawMessageDelivery=true >/dev/null
done

echo "[init-localstack] Mensageria pronta: ${TOPIC_ARN}"
