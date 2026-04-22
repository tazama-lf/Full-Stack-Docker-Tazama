# SPDX-License-Identifier: Apache-2.0

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.prefix}-vpc" }
}

# --- Internet Gateway ---

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-igw" }
}

# --- Public subnets (two AZs required for ALB) ---

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.prefix}-public-${count.index + 1}" }
}

# --- Private subnet (all three EC2 instances at fixed IPs) ---

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zones[0]
  tags              = { Name = "${var.prefix}-private" }
}

# --- NAT Gateway (private instances need internet for package installs / ghcr.io pulls) ---

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.prefix}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.prefix}-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}

# --- Route tables ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.prefix}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.prefix}-rt-private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --- EC2 Instance Connect Endpoint (EICE) ---
# Allows SSH to private instances without opening port 22 to the internet.
# The EICE endpoint itself gets a dedicated SG that allows outbound TCP 22
# only to the private subnet - no inbound rules required.

resource "aws_security_group" "eice" {
  name        = "${var.prefix}-eice-sg"
  description = "EC2 Instance Connect Endpoint - outbound SSH to private subnet only"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "SSH to private subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  tags = { Name = "${var.prefix}-eice-sg" }
}

resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = aws_subnet.private.id
  security_group_ids = [aws_security_group.eice.id]
  tags               = { Name = "${var.prefix}-eice" }
}
