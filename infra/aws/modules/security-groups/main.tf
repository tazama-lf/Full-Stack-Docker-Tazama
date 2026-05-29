# SPDX-License-Identifier: Apache-2.0

# --- Application Load Balancer SG ---
# Default mode: port-based HTTP listeners, one per service.
# Each service is reachable at http://<alb-dns>:<port> — same ports as the
# local Docker deployment, so Postman works without reconfiguration.
# When upgrading to the custom-domain HTTPS mode (Phase F), port 443 is used
# for all services and ports 3005-8088 can be removed from this SG.

resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb-sg"
  description = "ALB - inbound HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  # HTTPS - used when custom domain + ACM cert is configured (Phase F)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Server A service ports
  ingress {
    description = "TMS API"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Admin API"
    from_port   = 5100
    to_port     = 5100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Auth Service"
    from_port   = 3020
    to_port     = 3020
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Keycloak"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "pgAdmin (Server A)"
    from_port   = 5050
    to_port     = 5051
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Hasura"
    from_port   = 6100
    to_port     = 6100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "batch-ppa"
    from_port   = 4100
    to_port     = 4100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "DEAPI / DEMS (Server A)"
    from_port   = 3001
    to_port     = 3002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Server B service ports
  ingress {
    description = "TRS / TCS / CMS backends"
    from_port   = 3005
    to_port     = 3090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TCS / TRS / CMS frontends"
    from_port   = 5173
    to_port     = 5175
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Voila (CMS notebook server)"
    from_port   = 18866
    to_port     = 18866
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Server C service ports
  ingress {
    description = "NiFi UI"
    from_port   = 8088
    to_port     = 8088
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-alb-sg" }
}

# --- Server A (tazama-core) SG ---
# ALB-facing service ports + intra-subnet cross-server traffic + EICE SSH.

resource "aws_security_group" "server_a" {
  name        = "${var.prefix}-server-a-sg"
  description = "Server A (tazama-core) - ALB service ports, cross-server, EICE SSH"
  vpc_id      = var.vpc_id

  ingress {
    description     = "TMS API"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "DEAPI / DEMS / Auth service range"
    from_port       = 3001
    to_port         = 3020
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Admin API"
    from_port       = 5100
    to_port         = 5100
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Keycloak"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "pgAdmin (Server A)"
    from_port       = 5050
    to_port         = 5051
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Hasura"
    from_port       = 6100
    to_port         = 6100
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "batch-ppa"
    from_port       = 4100
    to_port         = 4100
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allows Server B/C to reach NATS (14222), PostgreSQL (15432), Valkey (16379), Auth (3020), etc.
  ingress {
    description = "Cross-server traffic from private subnet"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description     = "SSH from EICE endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.eice_sg_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-server-a-sg" }
}

# --- Server B (tazama-extensions) SG ---

resource "aws_security_group" "server_b" {
  name        = "${var.prefix}-server-b-sg"
  description = "Server B (tazama-extensions) - ALB service ports, cross-server, EICE SSH"
  vpc_id      = var.vpc_id

  ingress {
    description     = "TRS / TCS / CMS backends"
    from_port       = 3005
    to_port         = 3090
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "TCS / TRS / CMS frontends (Vite dev ports)"
    from_port       = 5173
    to_port         = 5175
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Voila (CMS notebook server)"
    from_port       = 18866
    to_port         = 18866
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "pgAdmin (Server B)"
    from_port       = 5051
    to_port         = 5051
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "CouchDB (ALB health check - port not exposed in ALB SG)"
    from_port       = 5984
    to_port         = 5984
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allows Server C to reach OpenSearch (9200) and PostgreSQL (15433) on Server B.
  ingress {
    description = "Cross-server traffic from private subnet"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description     = "SSH from EICE endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.eice_sg_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-server-b-sg" }
}

# --- Server C (tazama-biar) SG ---

resource "aws_security_group" "server_c" {
  name        = "${var.prefix}-server-c-sg"
  description = "Server C (tazama-biar) - ALB NiFi port, EICE SSH"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NiFi UI"
    from_port       = 8088
    to_port         = 8088
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "JupyterHub"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Automation Orchestrator"
    from_port       = 7619
    to_port         = 7619
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Datalakehouse API (via ALB)"
    from_port       = 8282
    to_port         = 8282
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # CMS backend on Server B calls the datalakehouse-api directly (not via ALB)
  ingress {
    description     = "CMS backend to Datalakehouse API (direct)"
    from_port       = 8282
    to_port         = 8282
    protocol        = "tcp"
    security_groups = [aws_security_group.server_b.id]
  }

  ingress {
    description     = "SSH from EICE endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.eice_sg_id]
  }

  egress {
    description = "All outbound (reaches Server A and B for NATS, Postgres, OpenSearch)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-server-c-sg" }
}
