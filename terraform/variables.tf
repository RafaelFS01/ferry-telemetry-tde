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
