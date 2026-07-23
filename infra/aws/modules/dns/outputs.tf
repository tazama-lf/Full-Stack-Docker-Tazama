# SPDX-License-Identifier: Apache-2.0

output "zone_id" {
  description = "Route 53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}
