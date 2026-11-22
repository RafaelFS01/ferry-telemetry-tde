# ==============================================================================
# Application Auto Scaling para Serviços ECS Fargate (SCRUM-30)
# Projeto: ferry-telemetry-tde | Critério C2 (Escalabilidade Horizontal)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Ingestion Service: Escalonamento Horizontal por CPU (ECSServiceAverageCPUUtilization)
# ------------------------------------------------------------------------------

resource "aws_appautoscaling_target" "ecs_ingestion_target" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.ferry_cluster.name}/${aws_ecs_service.ferry_central_ingestion.name}"
  min_capacity       = var.ecs_ingestion_min_capacity
  max_capacity       = var.ecs_ingestion_max_capacity
}

resource "aws_appautoscaling_policy" "ecs_ingestion_cpu_policy" {
  name               = "ferry-ingestion-cpu-target-tracking-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_ingestion_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_ingestion_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_ingestion_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.ecs_ingestion_cpu_target
    scale_in_cooldown  = 180
    scale_out_cooldown = 60
  }
}

# ------------------------------------------------------------------------------
# 2. Worker Service: Escalonamento Horizontal por Fila SQS (ApproximateNumberOfMessagesVisible)
# ------------------------------------------------------------------------------

resource "aws_appautoscaling_target" "ecs_worker_target" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.ferry_cluster.name}/${aws_ecs_service.ferry_central_worker.name}"
  min_capacity       = var.ecs_worker_min_capacity
  max_capacity       = var.ecs_worker_max_capacity
}

resource "aws_appautoscaling_policy" "ecs_worker_sqs_policy" {
  name               = "ferry-worker-sqs-target-tracking-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_worker_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_worker_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_worker_target.service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Average"

      dimensions {
        name  = "QueueName"
        value = aws_sqs_queue.ferry_db_writer_queue.name
      }
    }

    target_value       = var.ecs_worker_sqs_target_messages
    scale_in_cooldown  = 180
    scale_out_cooldown = 60
  }
}
