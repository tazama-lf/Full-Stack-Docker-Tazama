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

  lifecycle {
    # Deleting a hosted zone destroys the NS delegation at the registrar.
    # Never allow Tofu to destroy this resource automatically.
    prevent_destroy = true
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
    # Prevent accidental destruction of the validated certificate.
    # Re-issuing forces re-validation and breaks HTTPS until DNS propagates.
    prevent_destroy = true
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
    tms                     = var.target_group_arns["tms"]
    admin                   = var.target_group_arns["admin"]
    auth                    = var.target_group_arns["auth"]
    deapi                   = var.target_group_arns["deapi"]
    dems                    = var.target_group_arns["dems"]
    keycloak                = var.target_group_arns["keycloak"]
    pgadmin                 = var.target_group_arns["pgadmin"]
    hasura                  = var.target_group_arns["hasura"]
    tcs                     = var.target_group_arns["tcs-frontend"]
    tcs-api                 = var.target_group_arns["tcs-api"]
    trs                     = var.target_group_arns["trs-frontend"]
    trs-api                 = var.target_group_arns["trs-api"]
    cms                     = var.target_group_arns["cms-frontend"]
    cms-api                 = var.target_group_arns["cms-api"]
    voila                   = var.target_group_arns["voila"]
    pgadmin-ext             = var.target_group_arns["pgadmin-ext"]
    nifi                    = var.target_group_arns["nifi"]
    jupyter                 = var.target_group_arns["jupyterhub"]
    automation-orchestrator = var.target_group_arns["auto-orchestrator"]
    datalakehouse-api       = var.target_group_arns["datalakehouse-api"]
    batch-ppa               = var.target_group_arns["batch-ppa"]
    couchdb                 = var.target_group_arns["couchdb"]
  }

  # Explicit priorities — must match the actual AWS state exactly.
  # Never use index() which shifts every priority when the map changes.
  # To add new rules, append at the end with the next free integer.
  priority_map = {
    admin                   = 1
    auth                    = 2
    cms                     = 3
    cms-api                 = 4
    hasura                  = 5
    keycloak                = 6
    pgadmin                 = 8   # 7 is a gap left by prior partial applies
    nifi                    = 10  # 9 is a gap left by prior partial applies
    tcs-api                 = 11
    pgadmin-ext             = 12
    tcs                     = 13
    trs-api                 = 14
    tms                     = 15
    trs                     = 16
    automation-orchestrator = 17
    datalakehouse-api       = 18
    jupyter                 = 19
    deapi                   = 20
    dems                    = 21
    voila                   = 22
    batch-ppa               = 23
    couchdb                 = 24
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

# Host-based listener rule per subdomain
resource "aws_lb_listener_rule" "service" {
  for_each = local.subdomain_map

  listener_arn = aws_lb_listener.https.arn
  priority     = local.priority_map[each.key]

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
