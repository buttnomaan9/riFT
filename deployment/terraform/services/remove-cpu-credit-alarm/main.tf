data "aws_iam_policy_document" "iam_resource_policy_for_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "cloudwatch:DeleteAlarms",
      "ec2:DescribeInstances",
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarms"
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

resource "aws_lambda_function" "remove_alarms_lambda_function" {
  function_name    = local.name-prefix
  description      = "This lambda program deletes all alarms for instance. It is triggered from the CloudWatch, based on instance state change notification events."
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.iam_role_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  timeout          = "5"
  memory_size      = "128"

}
resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.remove_alarms_lambda_function.function_name}"
  retention_in_days = var.logs-retention-days
}

resource "aws_cloudwatch_event_rule" "remove_alarms_event_rule" {
  name        = local.name-prefix
  description = "Check for instance class."

  event_pattern = <<EOF
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {
    "state": ["terminated"]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "remove_alarms_rule_target" {
  rule = aws_cloudwatch_event_rule.remove_alarms_event_rule.name
  arn  = aws_lambda_function.remove_alarms_lambda_function.arn
}

resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${local.name-prefix}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remove_alarms_lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.remove_alarms_event_rule.arn
}

output "function_name" {
  value = aws_lambda_function.remove_alarms_lambda_function.function_name
}