# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "zone_name" {
  description = "Public hosted zone name to create (e.g. beta.tazama.org)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB (from module.alb.alb_dns_name)"
  type        = string
}

variable "alb_zone_id" {
  description = "Route 53 zone ID of the ALB (from module.alb.alb_zone_id) - required for alias records"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the ALB (from module.alb.alb_arn) - used to attach the HTTPS listener"
  type        = string
}

variable "target_group_arns" {
  description = "Map of service name -> target group ARN (from module.alb.target_group_arns)"
  type        = map(string)
}
