# ==============================================================================
# Outputs da Infraestrutura de Rede e Segurança
# Projeto: ferry-telemetry-tde | Módulo: Core Networking (SCRUM-7)
# ==============================================================================

# ------------------------------------------------------------------------------
# VPC e Subnets
# ------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID da VPC principal do ecossistema ferry-telemetry-tde"
  value       = aws_vpc.ferry_vpc.id
}

output "vpc_cidr" {
  description = "Bloco CIDR alocado para a VPC"
  value       = aws_vpc.ferry_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "Lista de IDs das subnets públicas (para ALB L7 e EC2 Barco)"
  value = [
    aws_subnet.ferry_public_subnet_a.id,
    aws_subnet.ferry_public_subnet_b.id
  ]
}

output "private_app_subnet_ids" {
  description = "Lista de IDs das subnets privadas para tarefas ECS Fargate"
  value = [
    aws_subnet.ferry_private_app_subnet_a.id,
    aws_subnet.ferry_private_app_subnet_b.id
  ]
}

output "private_db_subnet_ids" {
  description = "Lista de IDs das subnets privadas para o banco de dados RDS PostgreSQL 18"
  value = [
    aws_subnet.ferry_private_db_subnet_a.id,
    aws_subnet.ferry_private_db_subnet_b.id
  ]
}

output "db_subnet_group_name" {
  description = "Nome do DB Subnet Group (consumido pela tarefa SCRUM-8 RDS)"
  value       = aws_db_subnet_group.ferry_db_subnet_group.name
}

output "db_subnet_group_id" {
  description = "ID do DB Subnet Group"
  value       = aws_db_subnet_group.ferry_db_subnet_group.id
}

# ------------------------------------------------------------------------------
# Gateways
# ------------------------------------------------------------------------------

output "internet_gateway_id" {
  description = "ID do Internet Gateway principal"
  value       = aws_internet_gateway.ferry_igw.id
}

output "nat_gateway_id" {
  description = "ID do NAT Gateway para saída segura da camada privada"
  value       = aws_nat_gateway.ferry_nat.id
}

output "nat_gateway_public_ip" {
  description = "IP público estático do NAT Gateway"
  value       = aws_eip.nat_eip.public_ip
}

# ------------------------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------------------------

output "security_group_alb_id" {
  description = "ID do Security Group do Application Load Balancer L7"
  value       = aws_security_group.sg_ferry_alb.id
}

output "security_group_fargate_id" {
  description = "ID do Security Group das tarefas ECS Fargate"
  value       = aws_security_group.sg_ferry_fargate.id
}

output "security_group_rds_id" {
  description = "ID do Security Group do banco de dados RDS PostgreSQL 18"
  value       = aws_security_group.sg_ferry_rds.id
}

output "security_group_barco_id" {
  description = "ID do Security Group da instância EC2 do Nó Barco"
  value       = aws_security_group.sg_ferry_barco.id
}

# ------------------------------------------------------------------------------
# Banco de Dados Relacional AWS RDS PostgreSQL 18 (SCRUM-8)
# ------------------------------------------------------------------------------

output "rds_endpoint" {
  description = "Endpoint de conexão DNS e porta do RDS PostgreSQL 18"
  value       = aws_db_instance.ferry_postgres.endpoint
}

output "rds_address" {
  description = "Hostname DNS do banco de dados RDS PostgreSQL 18"
  value       = aws_db_instance.ferry_postgres.address
}

output "rds_port" {
  description = "Porta TCP do banco de dados RDS PostgreSQL (padrão 5432)"
  value       = aws_db_instance.ferry_postgres.port
}

output "rds_database_name" {
  description = "Nome do banco de dados relacional inicial"
  value       = aws_db_instance.ferry_postgres.db_name
}

output "rds_master_username" {
  description = "Nome do usuário administrador mestre do RDS"
  value       = aws_db_instance.ferry_postgres.username
  sensitive   = true
}

# ------------------------------------------------------------------------------
# Mensageria Assíncrona Amazon SNS & SQS (SCRUM-16)
# ------------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN do tópico SNS de telemetria para Fan-Out de eventos"
  value       = aws_sns_topic.ferry_telemetry_topic.arn
}

output "sns_topic_name" {
  description = "Nome do tópico SNS de telemetria"
  value       = aws_sns_topic.ferry_telemetry_topic.name
}

output "sqs_db_writer_queue_url" {
  description = "URL da fila SQS para persistência no PostgreSQL"
  value       = aws_sqs_queue.ferry_db_writer_queue.id
}

output "sqs_db_writer_queue_arn" {
  description = "ARN da fila SQS para persistência no PostgreSQL"
  value       = aws_sqs_queue.ferry_db_writer_queue.arn
}

output "sqs_alerts_queue_url" {
  description = "URL da fila SQS para notificações e alertas críticos"
  value       = aws_sqs_queue.ferry_alerts_queue.id
}

output "sqs_alerts_queue_arn" {
  description = "ARN da fila SQS para notificações e alertas críticos"
  value       = aws_sqs_queue.ferry_alerts_queue.arn
}

output "sqs_dlq_url" {
  description = "URL da Dead Letter Queue (DLQ) para mensagens descartadas após 5 tentativas"
  value       = aws_sqs_queue.ferry_telemetry_dlq.id
}

output "sqs_dlq_arn" {
  description = "ARN da Dead Letter Queue (DLQ) para mensagens descartadas após 5 tentativas"
  value       = aws_sqs_queue.ferry_telemetry_dlq.arn
}

# ------------------------------------------------------------------------------
# Application Load Balancer L7 gRPC & REST (SCRUM-18)
# ------------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS público do Application Load Balancer L7 para ingestão gRPC e tráfego REST"
  value       = aws_lb.ferry_alb.dns_name
}

output "alb_arn" {
  description = "ARN do Application Load Balancer L7"
  value       = aws_lb.ferry_alb.arn
}

output "alb_grpc_target_group_arn" {
  description = "ARN do Target Group gRPC HTTP/2 (Porta 50051)"
  value       = aws_lb_target_group.ferry_grpc_tg.arn
}

output "alb_rest_target_group_arn" {
  description = "ARN do Target Group REST / Dashboard (Porta 8000)"
  value       = aws_lb_target_group.ferry_rest_tg.arn
}

# ------------------------------------------------------------------------------
# Amazon ECS Cluster Fargate, Task Definitions e Services (SCRUM-18)
# ------------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "Nome do Cluster ECS Serverless Fargate"
  value       = aws_ecs_cluster.ferry_cluster.name
}

output "ecs_cluster_arn" {
  description = "ARN do Cluster ECS Serverless Fargate"
  value       = aws_ecs_cluster.ferry_cluster.arn
}

output "ecs_ingestion_service_name" {
  description = "Nome do ECS Service de Ingestão gRPC"
  value       = aws_ecs_service.ferry_central_ingestion.name
}

output "ecs_worker_service_name" {
  description = "Nome do ECS Service consumidor Worker SQS"
  value       = aws_ecs_service.ferry_central_worker.name
}

output "ecs_ingestion_task_definition_arn" {
  description = "ARN da Task Definition do serviço de Ingestão"
  value       = aws_ecs_task_definition.ferry_central_ingestion.arn
}

output "ecs_worker_task_definition_arn" {
  description = "ARN da Task Definition do serviço Worker SQS"
  value       = aws_ecs_task_definition.ferry_central_worker.arn
}

output "cloudwatch_log_group_ingestion" {
  description = "Nome do CloudWatch Log Group para o serviço de Ingestão"
  value       = aws_cloudwatch_log_group.ecs_ingestion_logs.name
}

output "cloudwatch_log_group_worker" {
  description = "Nome do CloudWatch Log Group para o serviço Worker SQS"
  value       = aws_cloudwatch_log_group.ecs_worker_logs.name
}

# ------------------------------------------------------------------------------
# Instância EC2 Simuladora do Nó Barco (SCRUM-19)
# ------------------------------------------------------------------------------

output "ec2_barco_instance_id" {
  description = "ID da instância EC2 do Nó Barco"
  value       = aws_instance.ferry_barco.id
}

output "ec2_barco_arn" {
  description = "ARN da instância EC2 do Nó Barco"
  value       = aws_instance.ferry_barco.arn
}

output "ec2_barco_elastic_ip" {
  description = "Endereço Elastic IP estático associado à instância do Barco"
  value       = aws_eip.ferry_barco_eip.public_ip
}

output "ec2_barco_private_ip" {
  description = "IP privado da instância do Barco na Subnet Pública B"
  value       = aws_instance.ferry_barco.private_ip
}





