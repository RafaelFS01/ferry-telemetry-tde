# ==============================================================================
# Topologia de Rede (VPC, Subnets Públicas e Privadas, Gateways e Roteamento)
# Projeto: ferry-telemetry-tde | Módulo: Core Networking (SCRUM-7)
# ==============================================================================

resource "aws_vpc" "ferry_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ferry-vpc"
    Tier = "Network"
  }
}

# ------------------------------------------------------------------------------
# Subnets Públicas (Multi-AZ para ALB e EC2 Barco)
# ------------------------------------------------------------------------------

resource "aws_subnet" "ferry_public_subnet_a" {
  vpc_id                  = aws_vpc.ferry_vpc.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "ferry-public-subnet-a"
    Tier = "Public"
  }
}

resource "aws_subnet" "ferry_public_subnet_b" {
  vpc_id                  = aws_vpc.ferry_vpc.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "ferry-public-subnet-b"
    Tier = "Public"
  }
}

# ------------------------------------------------------------------------------
# Subnets Privadas de Aplicação (ECS Fargate Tasks)
# ------------------------------------------------------------------------------

resource "aws_subnet" "ferry_private_app_subnet_a" {
  vpc_id                  = aws_vpc.ferry_vpc.id
  cidr_block              = var.private_app_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "ferry-private-app-subnet-a"
    Tier = "Private-App"
  }
}

resource "aws_subnet" "ferry_private_app_subnet_b" {
  vpc_id                  = aws_vpc.ferry_vpc.id
  cidr_block              = var.private_app_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "ferry-private-app-subnet-b"
    Tier = "Private-App"
  }
}

# ------------------------------------------------------------------------------
# Subnets Privadas de Dados (AWS RDS PostgreSQL 18)
# ------------------------------------------------------------------------------

resource "aws_subnet" "ferry_private_db_subnet_a" {
  vpc_id                  = aws_vpc.ferry_vpc.id
  cidr_block              = var.private_db_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "ferry-private-db-subnet-a"
    Tier = "Private-DB"
  }
}

resource "aws_subnet" "ferry_private_db_subnet_b" {
  vpc_id                  = aws_vpc.ferry_vpc.id
  cidr_block              = var.private_db_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "ferry-private-db-subnet-b"
    Tier = "Private-DB"
  }
}

resource "aws_db_subnet_group" "ferry_db_subnet_group" {
  name        = "ferry-db-subnet-group"
  description = "DB Subnet Group isolado para o cluster RDS PostgreSQL 18"
  subnet_ids = [
    aws_subnet.ferry_private_db_subnet_a.id,
    aws_subnet.ferry_private_db_subnet_b.id
  ]

  tags = {
    Name = "ferry-db-subnet-group"
    Tier = "Private-DB"
  }
}

# ------------------------------------------------------------------------------
# Internet Gateway e Roteamento Público
# ------------------------------------------------------------------------------

resource "aws_internet_gateway" "ferry_igw" {
  vpc_id = aws_vpc.ferry_vpc.id

  tags = {
    Name = "ferry-igw"
    Tier = "Network"
  }
}

resource "aws_route_table" "ferry_public_rt" {
  vpc_id = aws_vpc.ferry_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ferry_igw.id
  }

  tags = {
    Name = "ferry-public-route-table"
    Tier = "Public"
  }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.ferry_public_subnet_a.id
  route_table_id = aws_route_table.ferry_public_rt.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.ferry_public_subnet_b.id
  route_table_id = aws_route_table.ferry_public_rt.id
}

# ------------------------------------------------------------------------------
# NAT Gateway e Roteamento Privado da Aplicação
# ------------------------------------------------------------------------------

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "ferry-nat-eip"
    Tier = "Network"
  }
}

resource "aws_nat_gateway" "ferry_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.ferry_public_subnet_a.id

  tags = {
    Name = "ferry-nat-gateway"
    Tier = "Network"
  }

  depends_on = [aws_internet_gateway.ferry_igw]
}

resource "aws_route_table" "ferry_private_app_rt" {
  vpc_id = aws_vpc.ferry_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ferry_nat.id
  }

  tags = {
    Name = "ferry-private-app-route-table"
    Tier = "Private-App"
  }
}

resource "aws_route_table_association" "private_app_a_assoc" {
  subnet_id      = aws_subnet.ferry_private_app_subnet_a.id
  route_table_id = aws_route_table.ferry_private_app_rt.id
}

resource "aws_route_table_association" "private_app_b_assoc" {
  subnet_id      = aws_subnet.ferry_private_app_subnet_b.id
  route_table_id = aws_route_table.ferry_private_app_rt.id
}

# ------------------------------------------------------------------------------
# Roteamento Isolado para o Banco de Dados (Sem Saída para a Internet)
# ------------------------------------------------------------------------------

resource "aws_route_table" "ferry_isolated_db_rt" {
  vpc_id = aws_vpc.ferry_vpc.id

  tags = {
    Name = "ferry-isolated-db-route-table"
    Tier = "Private-DB"
  }
}

resource "aws_route_table_association" "private_db_a_assoc" {
  subnet_id      = aws_subnet.ferry_private_db_subnet_a.id
  route_table_id = aws_route_table.ferry_isolated_db_rt.id
}

resource "aws_route_table_association" "private_db_b_assoc" {
  subnet_id      = aws_subnet.ferry_private_db_subnet_b.id
  route_table_id = aws_route_table.ferry_isolated_db_rt.id
}

