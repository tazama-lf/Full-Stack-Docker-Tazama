# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend is intentionally empty here - config is supplied at init time:
  #   tofu init -backend-config=backend.conf
  # Copy backend.conf.example to backend.conf (gitignored) and fill in your
  # account ID before running init.
  backend "s3" {}
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

# ── IAM role: EC2 → SSM read-only ────────────────────────────────────────────
# Every instance needs this to read /tazama/gh_token from Parameter Store
# during bootstrap without embedding credentials in user_data.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "${var.prefix}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_readonly" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.prefix}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ── VPC ───────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"
  prefix = var.prefix
}

# ── Security Groups ───────────────────────────────────────────────────────────

module "security_groups" {
  source              = "./modules/security-groups"
  prefix              = var.prefix
  vpc_id              = module.vpc.vpc_id
  private_subnet_cidr = module.vpc.private_subnet_cidr
  eice_sg_id          = module.vpc.eice_sg_id
}

# ── AMI lookup: latest Amazon Linux 2023 x86_64 ───────────────────────────────

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── Bootstrap user_data (identical on all three instances) ────────────────────
# The template substitutes ${region}; bash variables use $${VAR} to escape
# OpenTofu interpolation and appear as ${VAR} in the rendered script.

locals {
  bootstrap = templatefile("${path.module}/templates/bootstrap.sh.tpl", {
    region = var.region
  })
}

# ── EC2: Server A - tazama-core (10.0.1.10) ───────────────────────────────────

module "server_a" {
  source               = "./modules/ec2"
  prefix               = var.prefix
  name                 = "core"
  subnet_id            = module.vpc.private_subnet_id
  private_ip           = "10.0.1.10"
  instance_type        = var.instance_type_a
  security_group_ids   = [module.security_groups.server_a_sg_id]
  key_name             = var.key_name
  ami_id               = data.aws_ami.al2023.id
  root_volume_size     = 50
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  user_data            = local.bootstrap
}

# ── EC2: Server B - tazama-extensions (10.0.1.20) ────────────────────────────

module "server_b" {
  source               = "./modules/ec2"
  prefix               = var.prefix
  name                 = "extensions"
  subnet_id            = module.vpc.private_subnet_id
  private_ip           = "10.0.1.20"
  instance_type        = var.instance_type_b
  security_group_ids   = [module.security_groups.server_b_sg_id]
  key_name             = var.key_name
  ami_id               = data.aws_ami.al2023.id
  root_volume_size     = 50
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  user_data            = local.bootstrap
}

# ── EC2: Server C - tazama-biar (10.0.1.30) ──────────────────────────────────

module "server_c" {
  source               = "./modules/ec2"
  prefix               = var.prefix
  name                 = "biar"
  subnet_id            = module.vpc.private_subnet_id
  private_ip           = "10.0.1.30"
  instance_type        = var.instance_type_c
  security_group_ids   = [module.security_groups.server_c_sg_id]
  key_name             = var.key_name
  ami_id               = data.aws_ami.al2023.id
  root_volume_size     = 100
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  user_data            = local.bootstrap
}

# ── DNS: Route 53 private hosted zone (tazama.internal) ───────────────────────

module "dns" {
  source  = "./modules/dns"
  prefix  = var.prefix
  vpc_id  = module.vpc.vpc_id
  records = {
    "core"       = module.server_a.private_ip
    "extensions" = module.server_b.private_ip
    "biar"       = module.server_c.private_ip
  }
}
