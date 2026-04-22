# SPDX-License-Identifier: Apache-2.0

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_id" {
  description = "ID of the private subnet (EC2 instances)"
  value       = aws_subnet.private.id
}

output "private_subnet_cidr" {
  description = "CIDR of the private subnet (used by SG intra-subnet rules)"
  value       = aws_subnet.private.cidr_block
}

output "eice_sg_id" {
  description = "Security group ID attached to the EICE endpoint"
  value       = aws_security_group.eice.id
}

output "eice_endpoint_id" {
  description = "EC2 Instance Connect Endpoint ID (used in SSH ProxyCommand)"
  value       = aws_ec2_instance_connect_endpoint.main.id
}
