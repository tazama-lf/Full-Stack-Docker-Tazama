# SPDX-License-Identifier: Apache-2.0

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.main.id
}

output "private_ip" {
  description = "Fixed private IP of the instance"
  value       = aws_instance.main.private_ip
}
