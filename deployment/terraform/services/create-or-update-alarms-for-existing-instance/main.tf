data "aws_iam_policy_document" "iam_resource_policy_for_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ec2:DescribeInstances",
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
  name        = "${var.resource-id}"
  description = "${var.resource-id}"
  path        = "/"
  policy      = data.aws_iam_policy_document.iam_resource_policy_for_lambda.json
}

resource "aws_iam_role" "iam_role_for_lambda" {
  name               = "${var.resource-id}"
  description        = "${var.resource-id}"
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

resource "aws_lambda_function" "create_or_update_alarms_lambda_function" {
  function_name    = var.resource-id
  description      = "The lambda puts events to update confirm of existing alarms or create alarms for existing instances. "
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.iam_role_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  timeout          = "5"
  memory_size      = "128"
  environment {
    variables = {
      UPDATE_ALARMS_CONFIG_NOTIFICATION                 = var.update-alarm-notification
      CREATE_ALARMS_FOR_EXISTING_INSTANCES_NOTIFICATION = var.create-alarm-notification
      UPDATE_ALARMS_OPERATION_TYPE                      = var.update-operation
      CREATE_ALARMS_OPERATION_TYPE                      = var.create-operation
      DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME                = var.ec2-event-bus-name
    }
  }

}

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.create_or_update_alarms_lambda_function.function_name}"
  retention_in_days = var.logs-retention-days
}


resource "aws_cloudwatch_event_rule" "create_or_update_alarms_event_rule" {
  event_bus_name = var.ec2-event-bus-name
  name           = var.resource-id
  description    = "Trigger downstream logic to create alarms for existing instances or update existing alarms config."

  event_pattern = <<EOF
{
  "source": ["lambda.amazonaws.com"],
  "detail-type": ["${var.create-alarm-notification}","${var.update-alarm-notification}"],
  "detail" : {
    "operation-type": ["${var.update-operation}","${var.create-operation}"],
    "function-name": ["${aws_lambda_function.create_or_update_alarms_lambda_function.function_name}"]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "create_or_update_alarms_rule_target" {
  event_bus_name = var.ec2-event-bus-name
  rule           = aws_cloudwatch_event_rule.create_or_update_alarms_event_rule.name
  arn            = var.arn-of-fn-which-is-invoked-by-this-event-rule
}

resource "aws_lambda_permission" "lambda_permission_for_create_or_update_alarms_rule_target_lambda" {
  statement_id  = "${var.resource-id}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = var.name-of-fn-which-is-invoked-by-this-event-rule
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.create_or_update_alarms_event_rule.arn
}

resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${var.resource-id}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_or_update_alarms_lambda_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns-topic-which-invoke-this-fn
}

#Subscribe to SNS topic which trigger the lambda function.
resource "aws_sns_topic_subscription" "send_notification_to_lambda" {
  topic_arn = var.sns-topic-which-invoke-this-fn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.create_or_update_alarms_lambda_function.arn
}

output "function_name" {
  value = aws_lambda_function.create_or_update_alarms_lambda_function.function_name
}
