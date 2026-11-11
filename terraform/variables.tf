# ==============================================================================
# Variáveis de Configuração de Rede e Infraestrutura
# Projeto: ferry-telemetry-tde | Módulo: Core Networking & Database (SCRUM-7, SCRUM-8)
# ==============================================================================

variable "aws_region" {
  description = "Região canônica da AWS para provisionamento da infraestrutura"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de implantação (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC principal"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_a_cidr" {
  description = "CIDR da Subnet Pública A (us-east-1a) para ALB e NAT Gateway"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_b_cidr" {
  description = "CIDR da Subnet Pública B (us-east-1b) para ALB e EC2 Nó Barco"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_app_subnet_a_cidr" {
  description = "CIDR da Subnet Privada App A (us-east-1a) para ECS Fargate Ingestion"
  type        = string
  default     = "10.0.10.0/24"
}

variable "private_app_subnet_b_cidr" {
  description = "CIDR da Subnet Privada App B (us-east-1b) para ECS Fargate SQS Worker"
  type        = string
  default     = "10.0.20.0/24"
}

variable "private_db_subnet_a_cidr" {
  description = "CIDR da Subnet Privada DB A (us-east-1a) para RDS PostgreSQL 18"
  type        = string
  default     = "10.0.100.0/24"
}

variable "private_db_subnet_b_cidr" {
  description = "CIDR da Subnet Privada DB B (us-east-1b) para RDS DB Subnet Group"
  type        = string
  default     = "10.0.200.0/24"
}

variable "admin_cidr" {
  description = "Bloco CIDR autorizado para acesso administrativo restrito (SSH)"
  type        = string
  default     = "0.0.0.0/0"
}

# ------------------------------------------------------------------------------
# Variáveis do Banco de Dados Relacional AWS RDS PostgreSQL 18 (SCRUM-8)
# ------------------------------------------------------------------------------

variable "db_engine_version" {
  description = "Versão do motor PostgreSQL gerenciado no RDS"
  type        = string
  default     = "18.6"
}

variable "db_instance_class" {
  description = "Classe da instância de computação RDS (ARM Graviton2 otimizado para custo)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Nome do banco de dados relacional inicial"
  type        = string
  default     = "ferry_telemetry"
}

variable "db_username" {
  description = "Nome do usuário administrador mestre do banco"
  type        = string
  default     = "ferry_admin"
}

variable "db_password" {
  description = "Senha do usuário administrador mestre do banco"
  type        = string
  sensitive   = true
  default     = "FerrySecure2026!"
}

variable "db_allocated_storage" {
  description = "Armazenamento alocado inicial em Gigabytes (gp3)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Limite máximo para auto-scaling de armazenamento (gp3)"
  type        = number
  default     = 50
}

variable "db_backup_retention_period" {
  description = "Dias de retenção de backups automáticos e logs WAL para PITR (1 dia para compatibilidade com AWS Free Tier)"
  type        = number
  default     = 1
}

# ------------------------------------------------------------------------------
# Variáveis de Mensageria Amazon SNS e SQS (SCRUM-16)
# ------------------------------------------------------------------------------

variable "sns_topic_name" {
  description = "Nome do tópico SNS para distribuição Fan-Out dos eventos de telemetria"
  type        = string
  default     = "ferry-telemetria-topic"
}

variable "sqs_db_writer_queue_name" {
  description = "Nome da fila SQS para persistência no banco de dados"
  type        = string
  default     = "ferry-db-writer-queue"
}

variable "sqs_alerts_queue_name" {
  description = "Nome da fila SQS para processamento de alertas críticos"
  type        = string
  default     = "ferry-alerts-queue"
}

variable "sqs_dlq_name" {
  description = "Nome da Dead Letter Queue (DLQ) para mensagens com falha"
  type        = string
  default     = "ferry-telemetry-dlq"
}

variable "sqs_max_receive_count" {
  description = "Número máximo de tentativas de entrega antes de enviar a mensagem para a DLQ"
  type        = number
  default     = 5
}

variable "sqs_visibility_timeout_seconds" {
  description = "Tempo de visibilidade da mensagem em segundos (tempo para o worker processar)"
  type        = number
  default     = 30
}

variable "sqs_message_retention_seconds" {
  description = "Tempo de retenção das mensagens nas filas principais em segundos (padrão: 4 dias)"
  type        = number
  default     = 345600
}

variable "sqs_dlq_retention_seconds" {
  description = "Tempo de retenção das mensagens na DLQ em segundos (padrão: 14 dias)"
  type        = number
  default     = 1209600
}

# ------------------------------------------------------------------------------
# Variáveis de Computação Serverless AWS ECS Fargate & ALB (SCRUM-18)
# ------------------------------------------------------------------------------

variable "ecs_ingestion_cpu" {
  description = "Unidades de CPU alocadas para a tarefa de Ingestão Fargate (512 = 0.5 vCPU)"
  type        = string
  default     = "512"
}

variable "ecs_ingestion_memory" {
  description = "Memória em MiB alocada para a tarefa de Ingestão Fargate (1024 = 1 GB)"
  type        = string
  default     = "1024"
}

variable "ecs_worker_cpu" {
  description = "Unidades de CPU alocadas para a tarefa Worker SQS Fargate (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
}

variable "ecs_worker_memory" {
  description = "Memória em MiB alocada para a tarefa Worker SQS Fargate (512 = 0.5 GB)"
  type        = string
  default     = "512"
}

variable "ecs_ingestion_desired_count" {
  description = "Número desejado de tarefas em execução para o serviço de Ingestão"
  type        = number
  default     = 1
}

variable "ecs_worker_desired_count" {
  description = "Número desejado de tarefas em execução para o serviço Worker SQS"
  type        = number
  default     = 1
}

variable "ecs_ingestion_image" {
  description = "URI da imagem Docker para o serviço de Ingestão gRPC (central-ingestion)"
  type        = string
  default     = "public.ecr.aws/docker/library/python:3.14-slim"
}

variable "ecs_worker_image" {
  description = "URI da imagem Docker para o serviço consumidor Worker SQS (central-worker)"
  type        = string
  default     = "public.ecr.aws/docker/library/python:3.14-slim"
}

variable "ecs_log_retention_days" {
  description = "Dias de retenção dos logs de contêiner no CloudWatch Logs"
  type        = number
  default     = 7
}


