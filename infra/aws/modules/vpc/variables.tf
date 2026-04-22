# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "tazama"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (must span two AZs for ALB)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (hosts all three EC2 instances)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zones" {
  description = "Two AZs in the region (public subnets in both; private subnet in first)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}
