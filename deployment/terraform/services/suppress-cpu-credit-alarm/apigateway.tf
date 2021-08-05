resource "aws_api_gateway_resource" "suppress_cpu_credit_alarm_resource" {
  rest_api_id = var.api-gateway-id
  parent_id   = var.api-gateway-root-resource-id
  path_part   = var.suppress-api-uri
}

resource "aws_api_gateway_method" "suppress_cpu_credit_alarm_method" {
  rest_api_id   = var.api-gateway-id
  resource_id   = aws_api_gateway_resource.suppress_cpu_credit_alarm_resource.id
  http_method   = "GET"
  authorization = "AWS_IAM"
  request_parameters = {
    "method.request.querystring.instance-id" = true
  }

  #api_key_required = true
}

resource "aws_api_gateway_integration" "suppress_cpu_credit_alarm_api_integration" {
  rest_api_id             = var.api-gateway-id
  resource_id             = aws_api_gateway_resource.suppress_cpu_credit_alarm_resource.id
  http_method             = aws_api_gateway_method.suppress_cpu_credit_alarm_method.http_method
  integration_http_method = "POST"

  #type                    = "AWS_PROXY"
  type = "AWS"
  uri  = aws_lambda_function.suppress_cpu_alarm_lambda_function.invoke_arn

  request_parameters = {
    "integration.request.querystring.instance-id" = "method.request.querystring.instance-id"
  }

  request_templates = {
    "application/json" = <<EOF
{
   "instance-id": "$input.params('instance-id')"
}
EOF
  }

  passthrough_behavior = "WHEN_NO_TEMPLATES"
}

resource "aws_lambda_permission" "lambda_permission_for_lambda" {
  statement_id  = "${local.name-prefix}-lambda-exec"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.suppress_cpu_alarm_lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.api-gateway-id}/*/${aws_api_gateway_method.suppress_cpu_credit_alarm_method.http_method}${aws_api_gateway_resource.suppress_cpu_credit_alarm_resource.path}"
}

resource "aws_api_gateway_method_response" "status_200_suppress_cpu_credit_alarm" {
  rest_api_id = var.api-gateway-id
  resource_id = aws_api_gateway_resource.suppress_cpu_credit_alarm_resource.id
  http_method = aws_api_gateway_method.suppress_cpu_credit_alarm_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Timestamp"                   = true
    "method.response.header.Content-Length"              = true
    "method.response.header.Content-Type"                = true
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    #"application/json" = "Empty"
    "text/html" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "status_200_suppress_cpu_credit_alarm" {
  depends_on = [aws_api_gateway_integration.suppress_cpu_credit_alarm_api_integration]

  rest_api_id = var.api-gateway-id
  resource_id = aws_api_gateway_resource.suppress_cpu_credit_alarm_resource.id
  http_method = aws_api_gateway_method.suppress_cpu_credit_alarm_method.http_method
  status_code = aws_api_gateway_method_response.status_200_suppress_cpu_credit_alarm.status_code

  response_parameters = {
    #"method.response.header.Timestamp"                   = "integration.response.header.Date"
    #"method.response.header.Content-Length"              = "integration.response.header.Content-Length"
    "method.response.header.Content-Type" = "'text/html'"

    #"method.response.header.Access-Control-Allow-Origin" = "integration.response.header.Access-Control-Allow-Origin"
  }

  response_templates = {
    "text/html" = "$input.path('$')"
  }
}

resource "aws_api_gateway_deployment" "deployment_suppress_cpu_credit_alarm" {
  rest_api_id = var.api-gateway-id
  stage_name  = local.name-prefix
  depends_on  = [aws_api_gateway_integration.suppress_cpu_credit_alarm_api_integration]
}

resource "aws_api_gateway_usage_plan" "api_gateway_usage_plan_suppress_cpu_credit_alarm" {
  name        = local.name-prefix
  description = local.name-prefix

  api_stages {
    api_id = var.api-gateway-id
    stage  = local.name-prefix
  }

  quota_settings {
    limit  = 10000
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 20
    rate_limit  = 20
  }

  depends_on = [aws_api_gateway_deployment.deployment_suppress_cpu_credit_alarm]
}

resource "aws_api_gateway_api_key" "api_key_suppress_cpu_credit_alarm" {
  name = local.name-prefix
}

output "api_url" {
  value = aws_api_gateway_deployment.deployment_suppress_cpu_credit_alarm.invoke_url
}

output "stage_name" {
  value = local.name-prefix
}
