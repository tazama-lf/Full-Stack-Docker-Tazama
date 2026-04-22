# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Prefix applied to all resource names (e.g. tazama-vpc, tazama-core)"
  type        = string
  default     = "tazama"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI named profile to use for authentication"
  type        = string
  default     = "tazama"
}

variable "key_name" {
  description = "EC2 key pair name - created in Phase B step B.7 (default: tazama-aws)"
  type        = string
}

variable "instance_type_a" {
  description = "EC2 instance type for Server A (tazama-core)"
  type        = string
  default     = "t3.xlarge"
}

variable "instance_type_b" {
  description = "EC2 instance type for Server B (tazama-extensions)"
  type        = string
  default     = "t3.xlarge"
}

variable "instance_type_c" {
  description = "EC2 instance type for Server C (tazama-biar - NiFi + Solr + Ozone)"
  type        = string
  default     = "r5.2xlarge"
}

# ---------------------------------------------------------------------------
# Phase E — optional ALB (public sandbox)
# ---------------------------------------------------------------------------
variable "enable_alb" {
  description = <<-EOT
    Set to true to deploy the Application Load Balancer (Phase E option 2).
    Creates one internet-facing ALB with port-based HTTP listeners for all
    services. When false, services are only reachable via SSH tunnelling.
  EOT
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Phase G — optional custom domain upgrade
# ---------------------------------------------------------------------------
variable "enable_custom_domain" {
  description = <<-EOT
    Set to true to activate Phase F: creates a Route 53 public zone for
    domain_zone, issues an ACM wildcard cert, and switches the ALB to
    HTTPS with host-based routing (*.domain_zone).
    Prerequisite: subdomain NS delegation must be in place at the registrar.
  EOT
  type        = bool
  default     = false
}

variable "domain_zone" {
  description = "Public hosted zone name for custom domain (Phase G). Only used when enable_custom_domain = true."
  type        = string
  default     = "beta.tazama.org"
}

variable "state_bucket" {
  description = "Name of the S3 bucket used for OpenTofu state (e.g. tazama-tofu-state-<account-id>). Also used as the staging bucket for large-file transfers (lakehouse-staging/ prefix)."
  type        = string
}
