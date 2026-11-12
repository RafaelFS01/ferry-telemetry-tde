# ==============================================================================
# Amazon ECS Fargate, Task Definitions, IAM Roles e CloudWatch Logs
# Projeto: ferry-telemetry-tde | Módulo: Compute Serverless (SCRUM-18)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Cluster ECS Serverless (Sem Gerenciamento de Servidores EC2)
# ------------------------------------------------------------------------------

resource "aws_ecs_cluster" "ferry_cluster" {
  name = "ferry-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "ferry-cluster-${var.environment}"
    Component   = "Compute"
    Tier        = "Serverless"
    Environment = var.environment
  }
}

resource "aws_ecs_cluster_capacity_providers" "ferry_cluster_cp" {
  cluster_name = aws_ecs_cluster.ferry_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ------------------------------------------------------------------------------
# 2. CloudWatch Log Groups com Retenção Otimizada
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs_ingestion_logs" {
  name              = "/ecs/ferry-central-ingestion-${var.environment}"
  retention_in_days = var.ecs_log_retention_days

  tags = {
    Name        = "ecs-ingestion-logs"
    Component   = "Logging"
    Service     = "ferry-central-ingestion"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "ecs_worker_logs" {
  name              = "/ecs/ferry-central-worker-${var.environment}"
  retention_in_days = var.ecs_log_retention_days

  tags = {
    Name        = "ecs-worker-logs"
    Component   = "Logging"
    Service     = "ferry-central-worker"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 3. Políticas e Roles IAM com Princípio do Menor Privilégio
# ------------------------------------------------------------------------------

# Trust Policy para tarefas ECS
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 3.1. Task Execution Role (Download de Imagens do ECR e Envio de Logs)
resource "aws_iam_role" "ecs_execution_role" {
  name               = "ferry-ecs-execution-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name        = "ferry-ecs-execution-role-${var.environment}"
    Component   = "IAM"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 3.2. Task Role: Ingestion Service (Acesso ao Tópico SNS para Publicação de Eventos)
resource "aws_iam_role" "ecs_ingestion_task_role" {
  name               = "ferry-ecs-ingestion-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name        = "ferry-ecs-ingestion-task-role-${var.environment}"
    Component   = "IAM"
    Service     = "ferry-central-ingestion"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "ecs_ingestion_policy" {
  name = "ferry-ingestion-sns-policy"
  role = aws_iam_role.ecs_ingestion_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.ferry_telemetry_topic.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# 3.3. Task Role: Worker Service (Acesso à Fila SQS para Consumo e Remoção em Lote)
resource "aws_iam_role" "ecs_worker_task_role" {
  name               = "ferry-ecs-worker-task-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json

  tags = {
    Name        = "ferry-ecs-worker-task-role-${var.environment}"
    Component   = "IAM"
    Service     = "ferry-central-worker"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "ecs_worker_policy" {
  name = "ferry-worker-sqs-policy"
  role = aws_iam_role.ecs_worker_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:DeleteMessageBatch",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.ferry_db_writer_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 4. Task Definitions para Ingestão e Worker
# ------------------------------------------------------------------------------

# 4.1. Task Definition: Ingestão gRPC & API REST (0.5 vCPU / 1 GB RAM)
resource "aws_ecs_task_definition" "ferry_central_ingestion" {
  family                   = "ferry-central-ingestion-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_ingestion_cpu
  memory                   = var.ecs_ingestion_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_ingestion_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "ferry-central-ingestion"
      image     = var.ecs_ingestion_image
      essential = true
      command   = ["python3", "-c", "import time; print('Fargate Ingestion Service Running'); time.sleep(86400)"]

      portMappings = [
        {
          containerPort = 50051
          hostPort      = 50051
          protocol      = "tcp"
        },
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "GRPC_PORT"
          value = "50051"
        },
        {
          name  = "REST_PORT"
          value = "8000"
        },
        {
          name  = "TOPIC_ARN"
          value = aws_sns_topic.ferry_telemetry_topic.arn
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.ferry_postgres.address
        },
        {
          name  = "DB_PORT"
          value = tostring(aws_db_instance.ferry_postgres.port)
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "DB_PASSWORD"
          value = var.db_password
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_ingestion_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ingestion"
        }
      }
    }
  ])

  tags = {
    Name        = "ferry-central-ingestion-${var.environment}"
    Component   = "Compute"
    Service     = "Ingestion"
    Environment = var.environment
  }
}

# 4.2. Task Definition: Consumidor Worker SQS (0.25 vCPU / 0.5 GB RAM)
resource "aws_ecs_task_definition" "ferry_central_worker" {
  family                   = "ferry-central-worker-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_worker_cpu
  memory                   = var.ecs_worker_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_worker_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "ferry-central-worker"
      image     = var.ecs_worker_image
      essential = true
      command   = ["python3", "-c", "import time; print('Fargate Worker Service Running'); time.sleep(86400)"]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.ferry_db_writer_queue.url
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.ferry_postgres.address
        },
        {
          name  = "DB_PORT"
          value = tostring(aws_db_instance.ferry_postgres.port)
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "DB_PASSWORD"
          value = var.db_password
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_worker_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])

  tags = {
    Name        = "ferry-central-worker-${var.environment}"
    Component   = "Compute"
    Service     = "Worker"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 5. ECS Services com Auto-Recuperação e Roteamento
# ------------------------------------------------------------------------------

# 5.1. ECS Service: Ingestion (Integrado ao ALB gRPC na Subnet Privada)
resource "aws_ecs_service" "ferry_central_ingestion" {
  name            = "ferry-central-ingestion-${var.environment}"
  cluster         = aws_ecs_cluster.ferry_cluster.id
  task_definition = aws_ecs_task_definition.ferry_central_ingestion.arn
  launch_type     = "FARGATE"
  desired_count   = var.ecs_ingestion_desired_count

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets = [
      aws_subnet.ferry_private_app_subnet_a.id,
      aws_subnet.ferry_private_app_subnet_b.id
    ]
    security_groups  = [aws_security_group.sg_ferry_fargate.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ferry_grpc_tg.arn
    container_name   = "ferry-central-ingestion"
    container_port   = 50051
  }

  depends_on = [aws_lb_listener.grpc_listener]

  tags = {
    Name        = "ferry-central-ingestion-${var.environment}"
    Component   = "Compute"
    Service     = "Ingestion"
    Environment = var.environment
  }
}

# 5.2. ECS Service: Worker SQS (Consumo Contínuo em Segundo Plano)
resource "aws_ecs_service" "ferry_central_worker" {
  name            = "ferry-central-worker-${var.environment}"
  cluster         = aws_ecs_cluster.ferry_cluster.id
  task_definition = aws_ecs_task_definition.ferry_central_worker.arn
  launch_type     = "FARGATE"
  desired_count   = var.ecs_worker_desired_count

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets = [
      aws_subnet.ferry_private_app_subnet_a.id,
      aws_subnet.ferry_private_app_subnet_b.id
    ]
    security_groups  = [aws_security_group.sg_ferry_fargate.id]
    assign_public_ip = false
  }

  tags = {
    Name        = "ferry-central-worker-${var.environment}"
    Component   = "Compute"
    Service     = "Worker"
    Environment = var.environment
  }
}
