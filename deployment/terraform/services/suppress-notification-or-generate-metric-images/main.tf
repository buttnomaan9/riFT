data "aws_iam_policy_document" "iam_resource_policy_for_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ec2:DescribeInstances",
      "events:PutEvents",
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

resource "aws_lambda_function" "generate_metric_images_lambda_function" {
  function_name    = local.name-prefix
  description      = "This lambda function generate images of the metric which are part of the alarm. "
  layers           = [var.lambda-layer-aws-powertools-and-more-arn]
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
      API_ENDPOINT                        = var.suppress-api-endpoint
      API_GATEWAY_HOST                    = "${var.suppress-apigateway-host}.${data.aws_region.current.name}.amazonaws.com"
      SUPPRESS_NOTIFICATION_URI           = var.suppress-api-uri
      CREDENTIAL_TO_SIGN_API_URL          = var.secret-name-which-store-access-key-and-secret-key-to-sign-api-url
      S3_BUCKET_TO_STORE_GENERATED_IMAGES = var.name-of-bucket-to-store-images
      FN_OUTCOME                          = var.outcome-of-this-fn-for-next-trigger
      NOTIFICATION_FROM_FN                = var.notification-of-this-fn-for-next-trigger
      DYNAMIC_EC2_MONITOR_EVENT_BUS_NAME  = var.ec2-event-bus-name
      SUPPRESS_TAG_NAME                   = var.suppress-tag-name
    }
  }
}

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.generate_metric_images_lambda_function.function_name}"
  retention_in_days = var.logs-retention-days
}


resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${local.name-prefix}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_metric_images_lambda_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns-topic-which-invoke-this-function
}

#Subscribe to SNS topic which trigger the lambda function.
resource "aws_sns_topic_subscription" "send_notification_to_lambda" {
  topic_arn = var.sns-topic-which-invoke-this-function
  protocol  = "lambda"
  endpoint  = aws_lambda_function.generate_metric_images_lambda_function.arn
}

#Event rule to trigger downstream send-notification functions. 
resource "aws_cloudwatch_event_rule" "post_alarm_state_notification_event_rule" {
  name           = local.name-prefix
  description    = "Post alarm state notifications to downstream functions."
  event_bus_name = var.ec2-event-bus-name
  event_pattern  = <<EOF
{
  "source": ["lambda.amazonaws.com"],
  "detail-type": ["${var.notification-of-this-fn-for-next-trigger}"],
  "detail" : {
    "function-name": ["${aws_lambda_function.generate_metric_images_lambda_function.function_name}"],
    "function-outcome": ["${var.outcome-of-this-fn-for-next-trigger}"]
  }
}
EOF
}

output "post_alarm_state_notification_event_rule_name" {
  value = aws_cloudwatch_event_rule.post_alarm_state_notification_event_rule.name
}

output "post_alarm_state_notification_event_rule_arn" {
  value = aws_cloudwatch_event_rule.post_alarm_state_notification_event_rule.arn
}

output "generate_metric_images_lambda_function_role_arn" {
  value = aws_iam_role.iam_role_for_lambda.arn
}


output "function_name" {
  value = aws_lambda_function.generate_metric_images_lambda_function.function_name
}