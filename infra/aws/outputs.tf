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
