locals {
  name-prefix = var.resource-id
  #lambda-layer-name = var.lambda-layer-aws-powertools-and-more-name-suffix
}
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}