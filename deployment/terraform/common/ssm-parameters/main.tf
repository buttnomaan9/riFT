resource "aws_ssm_parameter" "cpu_credit_alarm_threshold_ssm_parameter" {
  name  = "/rift/${var.resource-id}/config/alarms/cpu/credit/threshold"
  type  = "String"
  value = var.cpu-credit-alarm-threshold
}

resource "aws_ssm_parameter" "alarm_period_ssm_parameter" {
  name  = "/rift/${var.resource-id}/config/alarms/period"
  type  = "String"
  value = var.period
}

resource "aws_ssm_parameter" "alarm_datapoints_ssm_parameter" {
  name  = "/rift/${var.resource-id}/config/alarms/datapoints"
  type  = "String"
  value = var.datapoints
}

resource "aws_ssm_parameter" "alarm_evaluation_period_ssm_parameter" {
  name  = "/rift/${var.resource-id}/config/alarms/evaluation-periods"
  type  = "String"
  value = var.evaluation-periods
}

resource "aws_ssm_parameter" "ms_teams_web_hook_url_ssm_parameter" {
  name  = "/rift/${var.resource-id}/config/subscribers/ms-teams/webhook/url"
  type  = "String"
  value = var.ms-teams-webhook-url
}

resource "aws_ssm_parameter" "maintenance_sns_topic" {
  name  = "/rift/${var.resource-id}/sns/topic/maintenance"
  type  = "String"
  value = var.maintenance-topic-arn
}

output "threshold_param_name" {
  value = aws_ssm_parameter.cpu_credit_alarm_threshold_ssm_parameter.name
}

output "period_param_name" {
  value = aws_ssm_parameter.alarm_period_ssm_parameter.name
}

output "evaluation_period_param_name" {
  value = aws_ssm_parameter.alarm_evaluation_period_ssm_parameter.name
}

output "datapoints_param_name" {
  value = aws_ssm_parameter.alarm_datapoints_ssm_parameter.name
}

output "msteams_webhook_url_param_name" {
  value = aws_ssm_parameter.ms_teams_web_hook_url_ssm_parameter.name
}