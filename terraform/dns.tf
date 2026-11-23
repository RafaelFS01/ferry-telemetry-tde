# ==============================================================================
# DNS Público (Route 53) e Certificado TLS Público (ACM)
# Projeto: ferry-telemetry-tde | Módulo: DNS & Domínio Amigável (SCRUM-29)
# ==============================================================================
#
# A zona só responde depois que os nameservers do Registro.br apontam para ela
# (output route53_name_servers). Ordem do primeiro apply em docs/dns.md.

locals {
  dashboard_fqdn = "${var.dashboard_subdomain}.${var.domain_name}"
  captain_fqdn   = "${var.captain_subdomain}.${var.domain_name}"

  preserved_records = {
    for r in var.dns_preserved_records : "${r.name == "" ? "@" : r.name}-${r.type}" => r
  }
}

# ------------------------------------------------------------------------------
# 1. Zona pública
# ------------------------------------------------------------------------------

resource "aws_route53_zone" "public" {
  name    = var.domain_name
  comment = "Zona publica do ferry-telemetry-tde (SCRUM-29)"

  tags = {
    Name      = "ferry-zone-${var.environment}"
    Component = "DNS"
  }
}

# Registros que já existiam no Registro.br (site e e-mail continuam funcionando)
resource "aws_route53_record" "preserved" {
  for_each = local.preserved_records

  zone_id = aws_route53_zone.public.zone_id
  name    = each.value.name == "" ? var.domain_name : "${each.value.name}.${var.domain_name}"
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}

# ------------------------------------------------------------------------------
# 2. Endpoints do projeto
# ------------------------------------------------------------------------------

# Ingestão gRPC (:50051, mTLS com a CA privada do projeto)
resource "aws_route53_record" "telemetry" {
  zone_id = aws_route53_zone.public.zone_id
  name    = var.grpc_custom_domain
  type    = "A"

  alias {
    name                   = aws_lb.ferry_alb.dns_name
    zone_id                = aws_lb.ferry_alb.zone_id
    evaluate_target_health = false
  }
}

# Dashboard Cartográfico e API REST (:443 com certificado público)
resource "aws_route53_record" "dashboard" {
  zone_id = aws_route53_zone.public.zone_id
  name    = local.dashboard_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.ferry_alb.dns_name
    zone_id                = aws_lb.ferry_alb.zone_id
    evaluate_target_health = false
  }
}

# Painel do Capitão no Elastic IP da EC2 do Nó Barco
resource "aws_route53_record" "captain" {
  zone_id = aws_route53_zone.public.zone_id
  name    = local.captain_fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.ferry_barco_eip.public_ip]
}

# ------------------------------------------------------------------------------
# 3. Certificado público *.domínio validado por DNS
# ------------------------------------------------------------------------------

resource "aws_acm_certificate" "public" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "ferry-public-cert-${var.environment}"
    Component = "Security"
  }
}

resource "aws_route53_record" "public_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.public.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id         = aws_route53_zone.public.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  ttl             = 300
  records         = [each.value.resource_record_value]
  allow_overwrite = true
}

# Bloqueia até a ACM ver o registro, ou seja, até a delegação no Registro.br valer
resource "aws_acm_certificate_validation" "public" {
  certificate_arn         = aws_acm_certificate.public.arn
  validation_record_fqdns = [for r in aws_route53_record.public_cert_validation : r.fqdn]

  timeouts {
    create = "2h"
  }
}
