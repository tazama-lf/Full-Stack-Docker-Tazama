# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the two public subnets (ALB requires two AZs)"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "server_a_id" {
  description = "EC2 instance ID of Server A (tazama-core)"
  type        = string
}

variable "server_b_id" {
  description = "EC2 instance ID of Server B (tazama-extensions)"
  type        = string
}

variable "server_c_id" {
  description = "EC2 instance ID of Server C (tazama-biar)"
  type        = string
}
