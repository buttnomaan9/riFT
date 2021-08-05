#Lambda function

data "aws_iam_policy_document" "iam_resource_policy_for_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "sns:Publish",
      "ec2:DescribeInstances",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:GetMetricWidgetImage",
      "cloudwatch:ListMetrics",
      "s3:PutObject",
      "ec2:DescribeImages",
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "*",
    ]
  }
}

data "aws_iam_policy_document" "iam_trust_policy_for_lambda" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "iam_policy_for_lambda" {
  name        = local.name-prefix
  description = local.name-prefix
  path        = "/"
  policy      = data.aws_iam_policy_document.iam_resource_policy_for_lambda.json
}

resource "aws_iam_role" "iam_role_for_lambda" {
  name               = local.name-prefix
  description        = local.name-prefix
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.iam_trust_policy_for_lambda.json
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_attachment1" {
  role       = aws_iam_role.iam_role_for_lambda.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/lambda.zip"
}

resource "aws_lambda_function" "post_alarm_notification_state_to_ms_teams_lambda_function" {
  function_name    = local.name-prefix
  description      = "This lambda function sends alarm state change notifications to MS Teams channel if the alarm notification is not required to be suppressed."
  layers           = [var.lambda-layer-aws-powertools-and-more-arn]
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.iam_role_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  timeout          = "5"
  memory_size      = "128"

  environment {
    variables = {
      MS_TEAMS_WEB_HOOK_URL = var.ms-teams-web-hook-url
    }
  }

}
resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.post_alarm_notification_state_to_ms_teams_lambda_function.function_name}"
  retention_in_days = var.logs-retention-days
}

resource "aws_cloudwatch_event_target" "post_alarm_notification_state_to_ms_teams_rule_target" {
  event_bus_name = var.ec2-event-bus-name
  rule           = var.event-rule-name-which-trigger-this-fn
  arn            = aws_lambda_function.post_alarm_notification_state_to_ms_teams_lambda_function.arn
}

resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${local.name-prefix}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_alarm_notification_state_to_ms_teams_lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.event-rule-arn-which-trigger-this-fn
}

output "function_name" {
  value = aws_lambda_function.post_alarm_notification_state_to_ms_teams_lambda_function.function_name
}