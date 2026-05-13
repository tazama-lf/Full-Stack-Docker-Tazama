# SPDX-License-Identifier: Apache-2.0

# ── ALB ──────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.prefix}-alb" }
}

# ── Target groups ─────────────────────────────────────────────────────────────
# One target group per service port. Health checks use HTTP on the same port
# with a lightweight path. Adjust the health_check path per service if the
# service exposes a dedicated /health endpoint.

locals {
  # service_name -> { port, instance }
  # "instance" is resolved to the ID in each attachment below.
  services = {
    tms          = { port = 5000, server = "a" }
    admin        = { port = 5100, server = "a" }
    auth         = { port = 3020, server = "a" }
    deapi        = { port = 3001, server = "a" }
    dems         = { port = 3002, server = "a" }
    keycloak     = { port = 8080, server = "a" }
    pgadmin      = { port = 5050, server = "a" }
    hasura       = { port = 6100, server = "a" }
    batch-ppa    = { port = 4000, server = "a" }
    tcs-frontend = { port = 5173, server = "b" }
    tcs-api      = { port = 3010, server = "b" }
    trs-frontend = { port = 5174, server = "b" }
    trs-api      = { port = 3005, server = "b" }
    cms-frontend = { port = 5175, server = "b" }
    cms-api      = { port = 3090, server = "b" }
    voila        = { port = 18866, server = "b" }
    pgadmin-ext           = { port = 5051, server = "b" }
    nifi                    = { port = 8088, server = "c" }
    jupyterhub              = { port = 8000, server = "c" }
    auto-orchestrator       = { port = 7619, server = "c" }
    datalakehouse-api       = { port = 8282, server = "c" }
  }

  instance_map = {
    a = var.server_a_id
    b = var.server_b_id
    c = var.server_c_id
  }

  # Keycloak does not respond with 200 on /, use /health/ready instead.
  # CMS and TRS/TCS APIs (NestJS) have no /health route; Swagger UI at /api/docs returns 200.
  health_check_paths = {
    keycloak    = "/health/ready"
    nifi        = "/nifi-api/system-diagnostics"
    hasura      = "/healthz"
    pgadmin     = "/"
    pgadmin-ext = "/"
    jupyterhub  = "/hub/health"
    cms-api     = "/api/docs"
    trs-api     = "/api/docs"
    tcs-api     = "/api/docs"
    voila       = "/voila/"
  }
}

resource "aws_lb_target_group" "services" {
  for_each = local.services

  name        = "${var.prefix}-tg-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = lookup(local.health_check_paths, each.key, "/health")
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = { Name = "${var.prefix}-tg-${each.key}" }
}

# ── Target group attachments ──────────────────────────────────────────────────

resource "aws_lb_target_group_attachment" "services" {
  for_each = local.services

  target_group_arn = aws_lb_target_group.services[each.key].arn
  target_id        = local.instance_map[each.value.server]
  port             = each.value.port
}

# ── HTTP listeners: one per service port ──────────────────────────────────────
# Default mode: plain HTTP, port-based routing.
# Each service is reachable at http://<alb-dns>:<port>
# No host-based or path-based rules are needed — there is exactly one target
# group per listener, so the default action covers 100% of traffic.

resource "aws_lb_listener" "services" {
  for_each = local.services

  load_balancer_arn = aws_lb.main.arn
  port              = each.value.port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services[each.key].arn
  }

  tags = { Name = "${var.prefix}-listener-${each.key}" }
}
