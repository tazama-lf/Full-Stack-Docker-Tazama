# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR - allows cross-server communication within the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "eice_sg_id" {
  description = "Security group ID of the EICE endpoint (permitted to SSH into EC2 instances)"
  type        = string
}
