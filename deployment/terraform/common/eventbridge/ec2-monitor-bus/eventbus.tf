resource "aws_cloudwatch_event_bus" "dynamic_ec2_monitor_bus" {
  name = local.name-prefix
}


data "aws_iam_policy_document" "dynamic_ec2_monitor_bus_policy" {
  statement {
    sid    = "AccessToLambdaToPutEvents"
    effect = "Allow"
    actions = [
      "events:PutEvents",
    ]
    resources = [
      aws_cloudwatch_event_bus.dynamic_ec2_monitor_bus.arn
    ]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "event_bus_policy" {
  policy         = data.aws_iam_policy_document.dynamic_ec2_monitor_bus_policy.json
  event_bus_name = aws_cloudwatch_event_bus.dynamic_ec2_monitor_bus.name
}

output "main_bus_name" {
  value = aws_cloudwatch_event_bus.dynamic_ec2_monitor_bus.name
} 