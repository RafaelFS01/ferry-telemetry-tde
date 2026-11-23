# ==============================================================================
# Alarmes Operacionais no Amazon CloudWatch (SCRUM-33)
# Projeto: ferry-telemetry-tde | Critério C6 (Observabilidade e Alertas)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Dead Letter Queue (DLQ) não vazia (>= 1 mensagem retida)
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ferry_dlq_messages_alarm" {
  alarm_name          = "ferry-dlq-messages-alarm-${var.environment}"
  alarm_description   = "Alerta critico quando a Dead Letter Queue (ferry-telemetry-dlq) recebe ao menos 1 mensagem."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.ferry_telemetry_dlq.name
  }

  tags = {
    Name        = "ferry-dlq-messages-alarm-${var.environment}"
    Component   = "Observability"
    Severity    = "Critical"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 2. Erros HTTP 5XX nos targets do Application Load Balancer
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ferry_alb_target_5xx_alarm" {
  alarm_name          = "ferry-alb-target-5xx-alarm-${var.environment}"
  alarm_description   = "Alerta quando os targets atras do ALB retornam >= 5 respostas HTTP 5XX por minuto em 2 janelas seguidas."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.ferry_alb.arn_suffix
  }

  tags = {
    Name        = "ferry-alb-target-5xx-alarm-${var.environment}"
    Component   = "Observability"
    Severity    = "Warning"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 3. Saturação de CPU no Serviço ECS de Ingestão (>= 80%)
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ferry_ingestion_cpu_high_alarm" {
  alarm_name          = "ferry-ingestion-cpu-high-alarm-${var.environment}"
  alarm_description   = "Alerta de saturacao quando CPUUtilization do ferry-central-ingestion permanece >= 80% por 3 minutos."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.ferry_cluster.name
    ServiceName = aws_ecs_service.ferry_central_ingestion.name
  }

  tags = {
    Name        = "ferry-ingestion-cpu-high-alarm-${var.environment}"
    Component   = "Observability"
    Severity    = "Warning"
    Environment = var.environment
  }
}
