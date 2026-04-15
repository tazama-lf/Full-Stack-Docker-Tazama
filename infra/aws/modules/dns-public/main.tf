# SPDX-License-Identifier: Apache-2.0

# ---------------------------------------------------------------------------
# Route 53 public hosted zone
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "public" {
  name    = var.zone_name
  comment = "Managed by OpenTofu — ${var.prefix} public zone for ${var.zone_name}"

  tags = {
    Name = "${var.prefix}-public-zone"
  }
}

# ---------------------------------------------------------------------------
# ACM wildcard certificate (DNS-validated via the zone above)
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "wildcard" {
  domain_name               = "*.${var.zone_name}"
  subject_alternative_names = [var.zone_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.prefix}-wildcard-cert"
  }
}

# One CNAME record per unique validation record name.
# A wildcard cert (*.zone + zone) produces two domain_validation_options that
# share the same CNAME — the ellipsis (...) grouping operator merges duplicate
# keys so only one Route 53 record is created.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options :
    dvo.resource_record_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }...
  }

  zone_id = aws_route53_zone.public.zone_id
  name    = each.value[0].name
  type    = each.value[0].type
  ttl     = 60
  records = [each.value[0].record]
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------------------------------------------------------------------------
# Subdomain -> service routing map
# Each entry creates:
#   - a Route 53 alias record   (<subdomain>.zone_name -> ALB)
#   - a host-based listener rule (<subdomain>.zone_name -> target group)
# ---------------------------------------------------------------------------
locals {
  subdomain_map = {
    tms         = var.target_group_arns["tms"]
    admin       = var.target_group_arns["admin"]
    auth        = var.target_group_arns["auth"]
    keycloak    = var.target_group_arns["keycloak"]
    pgadmin     = var.target_group_arns["pgadmin"]
    hasura      = var.target_group_arns["hasura"]
    tcs         = var.target_group_arns["tcs-frontend"]
    tcs-api     = var.target_group_arns["tcs-api"]
    trs         = var.target_group_arns["trs-frontend"]
    trs-api     = var.target_group_arns["trs-api"]
    cms         = var.target_group_arns["cms-frontend"]
    cms-api     = var.target_group_arns["cms-api"]
    pgadmin-ext = var.target_group_arns["pgadmin-ext"]
    nifi        = var.target_group_arns["nifi"]
  }
}

# Route 53 alias record per subdomain
resource "aws_route53_record" "service" {
  for_each = local.subdomain_map

  zone_id = aws_route53_zone.public.zone_id
  name    = "${each.key}.${var.zone_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# HTTPS listener on the existing ALB
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = var.alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn

  # Default action: 404 for unknown hostnames
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Unknown host"
      status_code  = "404"
    }
  }

  tags = {
    Name = "${var.prefix}-https-listener"
  }
}

# Host-based listener rule per subdomain (priority 1-N)
resource "aws_lb_listener_rule" "service" {
  for_each = local.subdomain_map

  listener_arn = aws_lb_listener.https.arn
  priority     = index(keys(local.subdomain_map), each.key) + 1

  action {
    type             = "forward"
    target_group_arn = each.value
  }

  condition {
    host_header {
      values = ["${each.key}.${var.zone_name}"]
    }
  }

  tags = {
    Name = "${var.prefix}-${each.key}-https-rule"
  }
}
