# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "name" {
  description = "Instance name suffix (e.g. core, extensions, biar)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance into (private subnet)"
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP within the private subnet (10.0.1.10 / .20 / .30)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to attach"
  type        = list(string)
}

variable "key_name" {
  description = "EC2 key pair name (created in Phase B step B.7)"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (passed from data.aws_ami.al2023 in root module)"
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 50
}

variable "iam_instance_profile" {
  description = "IAM instance profile name - grants EC2 read-only SSM access for GH_TOKEN fetch"
  type        = string
}

variable "user_data" {
  description = "Bootstrap shell script rendered from bootstrap.sh.tpl"
  type        = string
}
