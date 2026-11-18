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
  name                 = "tg-ferry-grpc-${var.environment}"
  port                 = 50051
  protocol             = "HTTP"
  protocol_version     = "GRPC"
  vpc_id               = aws_vpc.ferry_vpc.id
  target_type          = "ip"
  deregistration_delay = 15

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/grpc.health.v1.Health/Check"
    matcher             = "0"
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
  name                 = "tg-ferry-rest-${var.environment}"
  port                 = 8000
  protocol             = "HTTP"
  protocol_version     = "HTTP1"
  vpc_id               = aws_vpc.ferry_vpc.id
  target_type          = "ip"
  deregistration_delay = 15

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
# 3.1. Target Group: Dashboard Cartográfico + Nginx Central (Porta 80) (SCRUM-27)
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "ferry_dashboard_tg" {
  name                 = "tg-ferry-dash-${var.environment}"
  port                 = 80
  protocol             = "HTTP"
  protocol_version     = "HTTP1"
  vpc_id               = aws_vpc.ferry_vpc.id
  target_type          = "ip"
  deregistration_delay = 15

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/healthz"
    matcher             = "200"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = {
    Name        = "tg-ferry-dash-${var.environment}"
    Component   = "Dashboard"
    Protocol    = "HTTP"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 4. Certificados CA, ALB TLS (com SAN do DNS do ALB) e Cliente Barco (SCRUM-27)
# ------------------------------------------------------------------------------

resource "tls_private_key" "ferry_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ferry_ca" {
  private_key_pem   = tls_private_key.ferry_ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "ferry-telemetry-ca"
    organization = "Ferry Telemetry TDE"
  }

  validity_period_hours = 87600

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "ferry_alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "ferry_alb" {
  private_key_pem = tls_private_key.ferry_alb.private_key_pem

  subject {
    common_name  = "ferry-alb.internal"
    organization = "Ferry Telemetry TDE"
  }

  dns_names = [
    aws_lb.ferry_alb.dns_name,
    "*.${var.aws_region}.elb.amazonaws.com",
    "ferry-alb.internal",
  ]
}

resource "tls_locally_signed_cert" "ferry_alb" {
  cert_request_pem   = tls_cert_request.ferry_alb.cert_request_pem
  ca_private_key_pem = tls_private_key.ferry_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ferry_ca.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "tls_private_key" "ferry_boat" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "ferry_boat" {
  private_key_pem = tls_private_key.ferry_boat.private_key_pem

  subject {
    common_name  = "ferry-ivete-sangalo"
    organization = "Ferry Telemetry TDE"
  }
}

resource "tls_locally_signed_cert" "ferry_boat" {
  cert_request_pem   = tls_cert_request.ferry_boat.cert_request_pem
  ca_private_key_pem = tls_private_key.ferry_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ferry_ca.cert_pem

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

resource "aws_acm_certificate" "ferry_alb_cert" {
  private_key       = tls_private_key.ferry_alb.private_key_pem
  certificate_body  = tls_locally_signed_cert.ferry_alb.cert_pem
  certificate_chain = tls_self_signed_cert.ferry_ca.cert_pem

  lifecycle {
    create_before_destroy = true
  }

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

# Listener HTTP Web (:80 -> Nginx / Dashboard Cartografico; /health -> REST API)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.ferry_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ferry_dashboard_tg.arn
  }

  tags = {
    Name      = "listener-ferry-http-${var.environment}"
    Protocol  = "HTTP"
    Port      = "80"
    Component = "LoadBalancer"
  }
}

resource "aws_lb_listener_rule" "rest_health_rule" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ferry_rest_tg.arn
  }

  condition {
    path_pattern {
      values = ["/health", "/api/v1/health"]
    }
  }
}
