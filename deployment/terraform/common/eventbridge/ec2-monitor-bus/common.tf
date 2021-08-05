locals {
  name-prefix = var.resource-id
}
data "aws_caller_identity" "current" {}