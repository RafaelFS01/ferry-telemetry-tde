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
# 3.2. Target Group: Painel do Capitão no Nó Barco (Porta 80)
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "ferry_captain_tg" {
  name        = "tg-ferry-captain-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.ferry_vpc.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    port                = "80"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = {
    Name        = "tg-ferry-captain-${var.environment}"
    Component   = "CaptainPanel"
    Protocol    = "HTTP"
    Environment = var.environment
  }
}

resource "aws_lb_target_group_attachment" "ferry_captain_attachment" {
  target_group_arn = aws_lb_target_group.ferry_captain_tg.arn
  target_id        = aws_instance.ferry_barco.id
  port             = 80
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

  dns_names = compact([
    aws_lb.ferry_alb.dns_name,
    "*.${var.aws_region}.elb.amazonaws.com",
    "ferry-alb.internal",
    var.grpc_custom_domain,
  ])
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
# 4.1. S3 Trust Store para mTLS Estrito no ALB (SCRUM-34)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "ferry_mtls_trust_store" {
  bucket_prefix = "ferry-mtls-truststore-${var.environment}-"
  force_destroy = true

  tags = {
    Name        = "ferry-mtls-truststore-${var.environment}"
    Component   = "Security"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "ferry_mtls_trust_store" {
  bucket = aws_s3_bucket.ferry_mtls_trust_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "ferry_ca_bundle" {
  bucket       = aws_s3_bucket.ferry_mtls_trust_store.id
  key          = "ca-bundle.pem"
  content      = tls_self_signed_cert.ferry_ca.cert_pem
  content_type = "application/x-pem-file"

  depends_on = [aws_s3_bucket_public_access_block.ferry_mtls_trust_store]
}

resource "aws_lb_trust_store" "ferry_ca" {
  name                             = "ferry-mtls-ca-${var.environment}"
  ca_certificates_bundle_s3_bucket = aws_s3_bucket.ferry_mtls_trust_store.bucket
  ca_certificates_bundle_s3_key    = aws_s3_object.ferry_ca_bundle.key

  depends_on = [
    aws_s3_bucket_public_access_block.ferry_mtls_trust_store,
    aws_s3_object.ferry_ca_bundle,
  ]

  tags = {
    Name        = "ferry-mtls-ca-${var.environment}"
    Component   = "Security"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 5. Listeners do ALB
# ------------------------------------------------------------------------------

# Listener gRPC (:50051 HTTPS com HTTP/2 ALPN e mTLS estrito)
resource "aws_lb_listener" "grpc_listener" {
  load_balancer_arn = aws_lb.ferry_alb.arn
  port              = 50051
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.ferry_alb_cert.arn

  mutual_authentication {
    mode                             = "verify"
    trust_store_arn                  = aws_lb_trust_store.ferry_ca.arn
    ignore_client_certificate_expiry = false
  }

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

# ------------------------------------------------------------------------------
# 6. HTTPS público do Dashboard (SCRUM-29)
# ------------------------------------------------------------------------------

# Listener HTTPS (:443) com o certificado público *.domínio emitido pela ACM
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.ferry_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.public.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ferry_dashboard_tg.arn
  }

  tags = {
    Name      = "listener-ferry-https-${var.environment}"
    Protocol  = "HTTPS"
    Port      = "443"
    Component = "LoadBalancer"
  }
}

resource "aws_lb_listener_rule" "https_rest_health_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
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

# http://painel.<domínio> sobe para HTTPS; o DNS bruto do ALB segue em HTTP
resource "aws_lb_listener_rule" "dashboard_https_redirect" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 1

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [local.dashboard_fqdn]
    }
  }
}

# http://capitao.<domínio> sobe para HTTPS
resource "aws_lb_listener_rule" "captain_https_redirect" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 2

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [local.captain_fqdn]
    }
  }
}

# https://capitao.<domínio> roteia para o Painel do Capitão no Nó Barco
resource "aws_lb_listener_rule" "https_captain_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ferry_captain_tg.arn
  }

  condition {
    host_header {
      values = [local.captain_fqdn]
    }
  }
}
