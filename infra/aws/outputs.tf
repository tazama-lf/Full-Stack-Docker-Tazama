# SPDX-License-Identifier: Apache-2.0

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "server_a_instance_id" {
  description = "Server A (tazama-core) EC2 instance ID"
  value       = module.server_a.instance_id
}

output "server_b_instance_id" {
  description = "Server B (tazama-extensions) EC2 instance ID"
  value       = module.server_b.instance_id
}

output "server_c_instance_id" {
  description = "Server C (tazama-biar) EC2 instance ID"
  value       = module.server_c.instance_id
}

output "server_a_private_ip" {
  description = "Server A private IP (10.0.1.10)"
  value       = module.server_a.private_ip
}

output "server_b_private_ip" {
  description = "Server B private IP (10.0.1.20)"
  value       = module.server_b.private_ip
}

output "server_c_private_ip" {
  description = "Server C private IP (10.0.1.30)"
  value       = module.server_c.private_ip
}

output "eice_endpoint_id" {
  description = "EC2 Instance Connect Endpoint ID - used in SSH ProxyCommand for Phase D connectivity"
  value       = module.vpc.eice_endpoint_id
}

output "dns_zone_id" {
  description = "Route 53 private hosted zone ID (tazama.internal)"
  value       = module.dns.zone_id
}

# ---------------------------------------------------------------------------
# Phase E outputs — only populated when enable_alb = true
# ---------------------------------------------------------------------------
output "alb_dns_name" {
  description = "ALB DNS name — base URL for all services (e.g. http://<alb_dns_name>:5000 for TMS). Empty when enable_alb = false."
  value       = var.enable_alb ? module.alb[0].alb_dns_name : ""
}

# ---------------------------------------------------------------------------
# Phase G outputs — only populated when enable_custom_domain = true
# ---------------------------------------------------------------------------
output "public_zone_nameservers" {
  description = "The four NS values to add at the registrar for subdomain delegation (Phase G). Empty when enable_custom_domain = false."
  value       = var.enable_custom_domain ? module.dns_public[0].zone_nameservers : []
}

output "public_zone_id" {
  description = "Route 53 public hosted zone ID (Phase G). Empty when enable_custom_domain = false."
  value       = var.enable_custom_domain ? module.dns_public[0].zone_id : ""
}

output "acm_certificate_arn" {
  description = "ARN of the validated ACM wildcard certificate (Phase G). Empty when enable_custom_domain = false."
  value       = var.enable_custom_domain ? module.dns_public[0].certificate_arn : ""
}
