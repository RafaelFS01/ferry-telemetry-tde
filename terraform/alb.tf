# ==============================================================================
# Application Load Balancer (ALB) L7 com Suporte a gRPC HTTP/2 e REST
# Projeto: ferry-telemetry-tde | Módulo: Load Balancing (SCRUM-18)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Application Load Balancer L7 (Público em Multi-AZ)
# ------------------------------------------------------------------------------

resource "aws_lb" "ferry_alb" {
  name               = "ferry-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_ferry_alb.id]
  subnets = [
    aws_subnet.ferry_public_subnet_a.id,
    aws_subnet.ferry_public_subnet_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name        = "ferry-alb-${var.environment}"
    Component   = "LoadBalancer"
    Tier        = "Public"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 2. Target Group: Ingestão gRPC sobre HTTP/2 (Porta 50051)
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "ferry_grpc_tg" {
  name             = "tg-ferry-grpc-${var.environment}"
  port             = 50051
  protocol         = "HTTP"
  protocol_version = "GRPC"
  vpc_id           = aws_vpc.ferry_vpc.id
  target_type      = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "0-99"
    port                = "50051"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = {
    Name        = "tg-ferry-grpc-${var.environment}"
    Component   = "Ingestion"
    Protocol    = "gRPC"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 3. Target Group: API REST / Dashboard (Porta 8000)
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "ferry_rest_tg" {
  name             = "tg-ferry-rest-${var.environment}"
  port             = 8000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  vpc_id           = aws_vpc.ferry_vpc.id
  target_type      = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/health"
    matcher             = "200"
    port                = "8000"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = {
    Name        = "tg-ferry-rest-${var.environment}"
    Component   = "RestApi"
    Protocol    = "HTTP"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 4. Certificado SSL/TLS para gRPC (Requisito AWS ALB para Target Groups GRPC)
# ------------------------------------------------------------------------------

resource "aws_acm_certificate" "ferry_alb_cert" {
  private_key      = file("${path.module}/certs/alb.key")
  certificate_body = file("${path.module}/certs/alb.crt")

  tags = {
    Name        = "ferry-alb-grpc-cert-${var.environment}"
    Component   = "Security"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 5. Listeners do ALB
# ------------------------------------------------------------------------------

# Listener gRPC (:50051 HTTPS com negociacao HTTP/2 ALPN)
resource "aws_lb_listener" "grpc_listener" {
  load_balancer_arn = aws_lb.ferry_alb.arn
  port              = 50051
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.ferry_alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ferry_grpc_tg.arn
  }

  tags = {
    Name      = "listener-ferry-grpc-${var.environment}"
    Protocol  = "gRPC-HTTPS"
    Port      = "50051"
    Component = "LoadBalancer"
  }
}

# Listener HTTP / REST (:80)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.ferry_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ferry_rest_tg.arn
  }

  tags = {
    Name      = "listener-ferry-http-${var.environment}"
    Protocol  = "HTTP"
    Port      = "80"
    Component = "LoadBalancer"
  }
}
