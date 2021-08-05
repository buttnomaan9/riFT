data "aws_iam_policy_document" "iam_resource_policy_for_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ec2:DescribeInstances",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric",
      "events:PutEvents"
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
  name        = "${local.name-prefix}"
  description = "${local.name-prefix}"
  path        = "/"
  policy      = data.aws_iam_policy_document.iam_resource_policy_for_lambda.json
}

resource "aws_iam_role" "iam_role_for_lambda" {
  name               = "${local.name-prefix}"
  description        = "${local.name-prefix}"
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

resource "aws_lambda_function" "check_composite_alarm_lambda_function" {
  function_name    = local.name-prefix
  description      = "This lambda to check if a composite already exists. It is triggered from the event bus rule."
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.iam_role_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  timeout          = "5"
  memory_size      = "128"

  environment {
    variables = {
      FN_OUTCOME                         = var.outcome-of-this-fn-for-next-trigger
      NOTIFICATION_FROM_FN               = var.notification-of-this-fn-for-next-trigger
      DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME = var.ec2-event-bus-name
    }
  }

}

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.check_composite_alarm_lambda_function.function_name}"
  retention_in_days = var.logs-retention-days
}

resource "aws_cloudwatch_event_rule" "check_composite_alarm_rule" {
  name           = local.name-prefix
  event_bus_name = var.ec2-event-bus-name
  description    = "Check for composite alarm."

  event_pattern = <<EOF
{
  "source": ["lambda.amazonaws.com"],
  "detail-type": ["${var.source-notification-which-invoke-this-fn}"],
  "detail" : {
    "function-name": ["${var.source-which-invoke-this-fn}"],
    "function-outcome": ["${var.outcome-which-trigger-this-fn}"]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "check_composite_alarm_rule_target" {
  event_bus_name = var.ec2-event-bus-name
  rule           = aws_cloudwatch_event_rule.check_composite_alarm_rule.name
  arn            = aws_lambda_function.check_composite_alarm_lambda_function.arn
}



resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${local.name-prefix}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_composite_alarm_lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.check_composite_alarm_rule.arn
}

output "function_arn" {
  value = aws_lambda_function.check_composite_alarm_lambda_function.arn
}

output "function_name" {
  value = aws_lambda_function.check_composite_alarm_lambda_function.function_name
}