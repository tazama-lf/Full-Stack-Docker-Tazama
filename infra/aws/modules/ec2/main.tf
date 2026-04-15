# SPDX-License-Identifier: Apache-2.0

resource "aws_instance" "main" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile
  user_data              = var.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  # IMDSv2 required - prevents SSRF-based credential theft via the metadata endpoint.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.prefix}-${var.name}" }

  # Prevent AMI drift from triggering instance replacement on subsequent applies.
  # The data.aws_ami lookup always resolves "most_recent", which changes as
  # Canonical publishes new Ubuntu images. Existing instances keep their
  # original AMI; only brand-new instances get the latest image.
  lifecycle {
    ignore_changes = [ami]
  }
}
