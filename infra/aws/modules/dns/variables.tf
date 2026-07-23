# SPDX-License-Identifier: Apache-2.0

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID - Route 53 private zone must be associated with the VPC"
  type        = string
}

variable "zone_name" {
  description = "Private hosted zone name"
  type        = string
  default     = "tazama.internal"
}

variable "records" {
  description = "Map of short hostname (without zone) to private IP address"
  type        = map(string)
  # Example:
  #   records = {
  #     "core"       = "10.0.1.10"
  #     "extensions" = "10.0.1.20"
  #     "biar"       = "10.0.1.30"
  #   }
}
