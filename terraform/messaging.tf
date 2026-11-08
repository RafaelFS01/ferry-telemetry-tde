# ==============================================================================
# Mensageria Assíncrona Desacoplada (Amazon SNS & SQS com Dead Letter Queue)
# Projeto: ferry-telemetry-tde | Módulo: Messaging (SCRUM-16)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Tópico SNS Central (Distribuição Fan-Out de Eventos)
# ------------------------------------------------------------------------------

resource "aws_sns_topic" "ferry_telemetry_topic" {
  name = var.sns_topic_name

  tags = {
    Name      = var.sns_topic_name
    Component = "Messaging"
    Tier      = "Event-Bus"
  }
}

# ------------------------------------------------------------------------------
# 2. Dead Letter Queue (DLQ)
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "ferry_telemetry_dlq" {
  name                      = var.sqs_dlq_name
  message_retention_seconds = var.sqs_dlq_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = {
    Name      = var.sqs_dlq_name
    Component = "Messaging"
    Tier      = "Dead-Letter-Queue"
  }
}

# ------------------------------------------------------------------------------
# 3. Fila SQS Principal (Persistência no DB via Consumer Worker)
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "ferry_db_writer_queue" {
  name                       = var.sqs_db_writer_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ferry_telemetry_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = {
    Name      = var.sqs_db_writer_queue_name
    Component = "Messaging"
    Tier      = "Worker-Queue"
  }
}

# ------------------------------------------------------------------------------
# 4. Fila SQS de Alertas (Notificações Críticas de Sensores)
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "ferry_alerts_queue" {
  name                       = var.sqs_alerts_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ferry_telemetry_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  tags = {
    Name      = var.sqs_alerts_queue_name
    Component = "Messaging"
    Tier      = "Alerts-Queue"
  }
}

# ------------------------------------------------------------------------------
# 5. Políticas de Acesso SQS (Autoriza o SNS a publicar nas filas)
# ------------------------------------------------------------------------------

resource "aws_sqs_queue_policy" "ferry_db_writer_queue_policy" {
  queue_url = aws_sqs_queue.ferry_db_writer_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSPublishToDBWriterQueue"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.ferry_db_writer_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.ferry_telemetry_topic.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "ferry_alerts_queue_policy" {
  queue_url = aws_sqs_queue.ferry_alerts_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSPublishToAlertsQueue"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.ferry_alerts_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.ferry_telemetry_topic.arn
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 6. Subscrições Fan-Out SNS -> SQS
# ------------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "db_writer_subscription" {
  topic_arn            = aws_sns_topic.ferry_telemetry_topic.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.ferry_db_writer_queue.arn
  raw_message_delivery = true
}

resource "aws_sns_topic_subscription" "alerts_subscription" {
  topic_arn            = aws_sns_topic.ferry_telemetry_topic.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.ferry_alerts_queue.arn
  raw_message_delivery = true
}
