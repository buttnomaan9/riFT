resource "aws_api_gateway_rest_api" "api_gateway_automated_post_cpu_credit_alarm_config_changes" {
  name        = local.name-prefix
  description = "API Gateway for ${var.resource-id}"
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway_automated_post_cpu_credit_alarm_config_changes.id
}

output "api_gateway_root_resource_id" {
  value = aws_api_gateway_rest_api.api_gateway_automated_post_cpu_credit_alarm_config_changes.root_resource_id
}
