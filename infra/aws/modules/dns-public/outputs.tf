# SPDX-License-Identifier: Apache-2.0

output "zone_id" {
  description = "Route 53 hosted zone ID for the public zone"
  value       = aws_route53_zone.public.zone_id
}

output "zone_nameservers" {
  description = "The four NS values to add at the registrar for subdomain delegation"
  value       = aws_route53_zone.public.name_servers
}

output "certificate_arn" {
  description = "ARN of the validated ACM wildcard certificate"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener attached to the ALB"
  value       = aws_lb_listener.https.arn
}
