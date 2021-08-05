data "aws_iam_policy_document" "iam_resource_policy_for_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "cloudwatch:PutMetricAlarm",
      "ec2:DescribeInstances",
      "events:PutEvents",
      "ssm:GetParameter"
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
  name        = "${local.name-prefix}_iam_policy"
  description = "${local.name-prefix}_iam_policy"
  path        = "/"
  policy      = data.aws_iam_policy_document.iam_resource_policy_for_lambda.json
}

resource "aws_iam_role" "iam_role_for_lambda" {
  name               = "${local.name-prefix}_iam_role"
  description        = "${local.name-prefix}_iam_role"
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

resource "aws_lambda_function" "create_cpu_utilization_alarm_lambda_function" {
  function_name    = local.name-prefix
  description      = "This lambda program creates baseline cpu utilization alarm for instance of T class."
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.iam_role_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  timeout          = "5"
  memory_size      = "128"
  #reserved_concurrent_executions = 1

  environment {
    variables = {
      DATAPOINTS                             = var.datapoints
      EVALUATION_PERIODS                     = var.evaluation-periods
      PERIOD                                 = var.period
      ADDITIONAL_DATAPOINTS                  = var.additional-datapoints
      ADDITIONAL_EVALUATION_PERIODS          = var.additional-evaluation-periods
      COMPUTE_INTENSIVE_WORKLOADS_REGIX_LIST = var.compute-intensive-workloads-regix-list
      FN_OUTCOME                             = var.outcome-of-this-fn-for-next-trigger
      NOTIFICATION_FROM_FN                   = var.notification-of-this-fn-for-next-trigger
      DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME     = var.ec2-event-bus-name
    }
  }
}

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.create_cpu_utilization_alarm_lambda_function.function_name}"
  retention_in_days = var.logs-retention-days
}


resource "aws_cloudwatch_event_rule" "create_cpu_utilization_alarm_event_rule" {
  name           = local.name-prefix
  description    = "Create cpu utilization alarm."
  event_bus_name = var.ec2-event-bus-name
  event_pattern  = <<EOF
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

resource "aws_cloudwatch_event_target" "create_cpu_utilization_alarm_rule_target" {
  event_bus_name = var.ec2-event-bus-name
  rule           = aws_cloudwatch_event_rule.create_cpu_utilization_alarm_event_rule.name
  arn            = aws_lambda_function.create_cpu_utilization_alarm_lambda_function.arn
}

resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${local.name-prefix}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_cpu_utilization_alarm_lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.create_cpu_utilization_alarm_event_rule.arn
}

output "function_name" {
  value = aws_lambda_function.create_cpu_utilization_alarm_lambda_function.function_name
}