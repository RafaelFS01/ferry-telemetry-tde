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

