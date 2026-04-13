# SPDX-License-Identifier: Apache-2.0

# --- Application Load Balancer SG ---
# Inbound HTTP/HTTPS from the internet; outbound to the EC2 instance SGs.

resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb-sg"
  description = "ALB - inbound HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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
