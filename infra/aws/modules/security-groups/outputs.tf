# SPDX-License-Identifier: Apache-2.0

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "server_a_sg_id" {
  value = aws_security_group.server_a.id
}

output "server_b_sg_id" {
  value = aws_security_group.server_b.id
}

output "server_c_sg_id" {
  value = aws_security_group.server_c.id
}
