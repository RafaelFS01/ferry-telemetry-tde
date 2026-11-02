# ==============================================================================
# Variáveis de Configuração de Rede e Infraestrutura
# Projeto: ferry-telemetry-tde | Módulo: Core Networking (SCRUM-7)
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

