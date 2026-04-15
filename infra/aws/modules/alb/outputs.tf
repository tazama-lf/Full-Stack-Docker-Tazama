# SPDX-License-Identifier: Apache-2.0

output "alb_dns_name" {
  description = "AWS-generated DNS name for the ALB (e.g. tazama-alb-1234567890.ap-south-1.elb.amazonaws.com)"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (needed for alias records when adding a custom domain)"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ALB ARN (needed by the dns-public module to attach HTTPS listeners)"
  value       = aws_lb.main.arn
}

output "target_group_arns" {
  description = "Map of service name -> target group ARN (needed by the dns-public module to wire HTTPS listener rules)"
  value       = { for k, v in aws_lb_target_group.services : k => v.arn }
}
