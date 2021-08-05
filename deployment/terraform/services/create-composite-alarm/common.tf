locals {
  name-prefix           = var.resource-id
  user-sns-topic-prefix = var.resource-id
}
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}