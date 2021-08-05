



resource "aws_sns_topic" "create_or_update_alarms_for_existing_ec2_sns_topic" {
  name         = var.resource-id
  display_name = var.resource-id
}


data "aws_iam_policy_document" "create_or_update_alarms_for_existing_ec2_sns_topic_policy" {
  policy_id = var.resource-id

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        "${data.aws_caller_identity.current.account_id}",
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      "${aws_sns_topic.create_or_update_alarms_for_existing_ec2_sns_topic.arn}",
    ]

    sid = "create_or_update_alarm_for_existing_ec2_sns_topic_statement_ID"
  }
}

resource "aws_sns_topic_policy" "create_or_update_alarms_for_existing_ec2_sns_topic_policy" {
  arn    = aws_sns_topic.create_or_update_alarms_for_existing_ec2_sns_topic.arn
  policy = data.aws_iam_policy_document.create_or_update_alarms_for_existing_ec2_sns_topic_policy.json
}

output "sns_topic_arn" {
  value = aws_sns_topic.create_or_update_alarms_for_existing_ec2_sns_topic.arn
}