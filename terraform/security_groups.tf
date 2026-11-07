# ==============================================================================
# Grupos de Segurança (Firewalls Perimetrais com Princípio do Menor Privilégio)
# Projeto: ferry-telemetry-tde | Módulo: Core Networking (SCRUM-7)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Security Group: Application Load Balancer L7 (Público)
# ------------------------------------------------------------------------------

resource "aws_security_group" "sg_ferry_alb" {
  name        = "sg_ferry_alb"
  description = "Controle de trafego publico para o Application Load Balancer L7 gRPC"
  vpc_id      = aws_vpc.ferry_vpc.id

  # Ingress: Entrada gRPC sobre HTTP/2
  ingress {
    description = "Ingestao gRPC HTTP/2 publica originada do Barco"
    from_port   = 50051
    to_port     = 50051
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: Entrada HTTP do Dashboard Central
  ingress {
    description = "Acesso HTTP ao Dashboard Cartografico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: Entrada HTTPS do Dashboard Central
  ingress {
    description = "Acesso HTTPS seguro ao Dashboard Cartografico"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_ferry_alb"
    Tier = "Public"
  }
}

# ------------------------------------------------------------------------------
# 2. Security Group: ECS Fargate Tasks (Privado)
# ------------------------------------------------------------------------------

resource "aws_security_group" "sg_ferry_fargate" {
  name        = "sg_ferry_fargate"
  description = "Regras para as tarefas ECS Fargate do No Central (Ingestao e Worker)"
  vpc_id      = aws_vpc.ferry_vpc.id

  # Egress: Chamadas HTTPS para APIs da AWS (SNS, SQS, CloudWatch, ECR) via NAT Gateway
  egress {
    description = "Acesso HTTPS de saida para servicos AWS (SNS, SQS, ECR, CloudWatch)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_ferry_fargate"
    Tier = "Private-App"
  }
}

# ------------------------------------------------------------------------------
# 3. Security Group: RDS PostgreSQL 18 (Privado e Isolado)
# ------------------------------------------------------------------------------

resource "aws_security_group" "sg_ferry_rds" {
  name        = "sg_ferry_rds"
  description = "Acesso transacional restrito exclusivamente a camada de aplicacao Fargate"
  vpc_id      = aws_vpc.ferry_vpc.id

  tags = {
    Name = "sg_ferry_rds"
    Tier = "Private-DB"
  }
}

# ------------------------------------------------------------------------------
# 4. Security Group: EC2 Nó Embarcado (Barco / Edge)
# ------------------------------------------------------------------------------

resource "aws_security_group" "sg_ferry_barco" {
  name        = "sg_ferry_barco"
  description = "Regras de seguranca para a instancia EC2 simuladora do Barco"
  vpc_id      = aws_vpc.ferry_vpc.id

  # Ingress: Nginx Painel do Capitão
  ingress {
    description = "Acesso HTTP ao Painel do Capitao via Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: Acesso Administrativo SSH restrito
  ingress {
    description = "Acesso SSH restrito para operacoes do operador"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Egress: Conexão gRPC para o ALB L7 da Central
  egress {
    description = "Trafego de telemetria gRPC saindo do Barco para o ALB Central"
    from_port   = 50051
    to_port     = 50051
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: Baixa de pacotes e imagens de contêineres
  egress {
    description = "Download de pacotes de SO e imagens de container"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Download seguro HTTPS de imagens Docker e dependencias"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: Sincronização de Tempo NTP (Amazon Time Sync)
  egress {
    description = "Sincronizacao NTP Chrony com Amazon Time Sync"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_ferry_barco"
    Tier = "Public"
  }
}

# ------------------------------------------------------------------------------
# 5. Regras Standalone Cruzadas (Desacoplamento e Anti-Ciclo)
# ------------------------------------------------------------------------------

# ALB -> Fargate (gRPC :50051)
resource "aws_security_group_rule" "alb_egress_fargate_grpc" {
  type                     = "egress"
  description              = "Roteamento gRPC do ALB para as tasks ECS Fargate"
  from_port                = 50051
  to_port                  = 50051
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_ferry_fargate.id
  security_group_id        = aws_security_group.sg_ferry_alb.id
}

resource "aws_security_group_rule" "fargate_ingress_alb_grpc" {
  type                     = "ingress"
  description              = "Ingress gRPC no Fargate autorizado exclusivamente a partir do ALB"
  from_port                = 50051
  to_port                  = 50051
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_ferry_alb.id
  security_group_id        = aws_security_group.sg_ferry_fargate.id
}

# ALB -> Fargate (REST API :8000)
resource "aws_security_group_rule" "alb_egress_fargate_rest" {
  type                     = "egress"
  description              = "Roteamento REST da Central para as tasks ECS Fargate"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_ferry_fargate.id
  security_group_id        = aws_security_group.sg_ferry_alb.id
}

resource "aws_security_group_rule" "fargate_ingress_alb_rest" {
  type                     = "ingress"
  description              = "Ingress REST no Fargate autorizado exclusivamente a partir do ALB"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_ferry_alb.id
  security_group_id        = aws_security_group.sg_ferry_fargate.id
}

# Fargate -> RDS (PostgreSQL :5432)
resource "aws_security_group_rule" "fargate_egress_rds" {
  type                     = "egress"
  description              = "Conexao PostgreSQL saindo das tasks Fargate para o RDS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_ferry_rds.id
  security_group_id        = aws_security_group.sg_ferry_fargate.id
}

resource "aws_security_group_rule" "rds_ingress_fargate" {
  type                     = "ingress"
  description              = "Acesso PostgreSQL autorizado exclusivamente a partir do Fargate"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg_ferry_fargate.id
  security_group_id        = aws_security_group.sg_ferry_rds.id
}

