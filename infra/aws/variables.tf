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
  default     = "t3.2xlarge"
}
