# Phase E: public sandbox — ALB
# Pass this file to tofu apply to deploy the Application Load Balancer.
# No editing required.
#
# Usage:
#   tofu apply -var-file terraform.tfvars -var-file alb.tfvars
#
# To remove the ALB, simply omit this file:
#   tofu apply -var-file terraform.tfvars

enable_alb = true
