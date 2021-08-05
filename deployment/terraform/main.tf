terraform {
  backend "s3" {
    encrypt = "true"
  }
  required_providers {
    aws = {
      version = ">= 3.49.0"
      source  = "hashicorp/aws"
    }

  }
}

provider "aws" {
  region  = var.aws-region
  profile = var.aws-profile
}


#This module the lambda layer used by various functions.
module "aws_lamda_power_tools_layer_for_automated_cpu_credit_alarms" {
  source      = "./common/lambda-layers"
  resource-id = "${var.lambda-layer-name-suffix}-${var.deployment-id}"
}
#This module deploys the SNS topic used as action by the composite alarm.
module "sns_topic_for_composite_alarm_action" {
  source      = "./common/sns-topics/receive-notification-from-cpu-credit-composite-alarm"
  resource-id = "${var.composite-alarm-sns-topic}-${var.deployment-id}"
}

#This module deploys the SNS topic to which various subscribers need to subscribe to reveive notifications.
module "sns_topic_for_end_subscribers" {
  source      = "./common/sns-topics/receive-ec2-notifications"
  resource-id = "${var.end-subscribers-sns-topic}-${var.deployment-id}"
}

#This module deploys an event bus used by functions for exchanging events to create alarms.
module "event_bridge_bus_for_dynamic_ec2_monitor" {
  source      = "./common/eventbridge/ec2-monitor-bus"
  resource-id = "${var.main-event-bus}-${var.deployment-id}"
}

# Create SSM parameters for alarm configuration.
module "ssm_parameters_for_alarm_configuration" {
  source                               = "./common/ssm-parameters"
  resource-id                          = "${var.deployment-id}"
  cpu-credit-alarm-threshold = var.number-of-cpu-credits-per-vcpu-hour
  datapoints = var.number-of-datapoints-to-evaluate
  period = var.period-of-evaluation-for-each-datapoint
  evaluation-periods = var.number-of-evaluation-periods
  ms-teams-webhook-url = var.placeholder-ms-teams-web-hook-url
  maintenance-topic-arn = module.sns_topic_to_create_or_update_alarms_for_existing_ec2.sns_topic_arn

}

# This module deploys a lambda function which check for the instance class.
module "create_lambda_to_check_instance_class" {
  source                                   = "./services/check-for-instance-class"
  resource-id                              = "${var.check-instance-type-fn}-${var.deployment-id}"
  ec2-event-bus-name                       = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  outcome-of-this-fn-for-next-trigger      = var.outcome-to-trigger-check-composite-alarm-fn
  notification-of-this-fn-for-next-trigger = var.notification-from-check-instance-class-fn
  logs-retention-days          = var.logs-retention-period
}

# This module deploys a lambda function which check for composite alarm.
module "create_lambda_to_check_composite_alarm" {
  source                                   = "./services/check-for-composite-alarm"
  resource-id                              = "${var.check-composite-alarm-fn}-${var.deployment-id}"
  ec2-event-bus-name                       = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  source-which-invoke-this-fn              = module.create_lambda_to_check_instance_class.function_name
  outcome-which-trigger-this-fn            = var.outcome-to-trigger-check-composite-alarm-fn
  outcome-of-this-fn-for-next-trigger      = var.outcome-to-trigger-create-cpu-credit-alarm-fn
  source-notification-which-invoke-this-fn = var.notification-from-check-instance-class-fn
  notification-of-this-fn-for-next-trigger = var.notification-from-check-composite-alarm-fn
  logs-retention-days          = var.logs-retention-period
}

# This module deploys a lambda function which creates a cpu credit alarm.
module "create_lambda_for_cpu_credit_alarm" {
  source                                   = "./services/create-cpu-credit-alarm"
  resource-id                              = "${var.create-credit-balance-alarm-fn}-${var.deployment-id}"
  period                                   = module.ssm_parameters_for_alarm_configuration.period_param_name # Period of evaluation for each datapoint.
  datapoints                               = module.ssm_parameters_for_alarm_configuration.datapoints_param_name       # Number of datapoints to evaluate.
  evaluation-periods                       = module.ssm_parameters_for_alarm_configuration.evaluation_period_param_name            # Number of evaluation periods. This is generally same as the number of datapoints.
  threshold                                = module.ssm_parameters_for_alarm_configuration.threshold_param_name     # Number of CPU credits used per vCPU-hour.
  additional-datapoints                    = 6
  additional-evaluation-periods            = 6
  compute-intensive-workloads-regix-list   = var.compute-intensive-workloads-regix-list
  ec2-event-bus-name                       = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  source-which-invoke-this-fn              = module.create_lambda_to_check_composite_alarm.function_name
  outcome-which-trigger-this-fn            = var.outcome-to-trigger-create-cpu-credit-alarm-fn
  outcome-of-this-fn-for-next-trigger      = var.outcome-to-trigger-create-cpu-utilization-alarm-fn
  source-notification-which-invoke-this-fn = var.notification-from-check-composite-alarm-fn
  notification-of-this-fn-for-next-trigger = var.notification-from-create-cpu-credit-balance-alarm-fn
  logs-retention-days          = var.logs-retention-period
}

# This module deploys a lambda function which creates a cpu utilization alarm.
module "create_lambda_for_cpu_utlization_alarm" {
  source                                   = "./services/create-cpu-utilization-alarm"
  resource-id                              = "${var.create-cpu-utilization-alarm-fn}-${var.deployment-id}"
  period                                   = module.ssm_parameters_for_alarm_configuration.period_param_name
  datapoints                               = module.ssm_parameters_for_alarm_configuration.datapoints_param_name
  evaluation-periods                       = module.ssm_parameters_for_alarm_configuration.evaluation_period_param_name
  additional-datapoints                    = 6
  additional-evaluation-periods            = 6
  compute-intensive-workloads-regix-list   = var.compute-intensive-workloads-regix-list
  ec2-event-bus-name                       = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  source-which-invoke-this-fn              = module.create_lambda_for_cpu_credit_alarm.function_name
  outcome-which-trigger-this-fn            = var.outcome-to-trigger-create-cpu-utilization-alarm-fn
  outcome-of-this-fn-for-next-trigger      = var.outcome-to-trigger-create-cpu-credit-composite-alarm-fn
  source-notification-which-invoke-this-fn = var.notification-from-create-cpu-credit-balance-alarm-fn
  notification-of-this-fn-for-next-trigger = var.notification-from-create-cpu-utilization-alarm-fn
logs-retention-days          = var.logs-retention-period
}

# This module deploys a lambda function which creates a composite alarm.
module "create_lambda_for_cpu_credit_composite_alarm" {
  source                                               = "./services/create-composite-alarm"
  resource-id                                          = "${var.cpu-credit-composite-fn}-${var.deployment-id}"
  ec2-event-bus-name                                   = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  sns-topic-which-receive-notification-from-this-alarm = module.sns_topic_for_composite_alarm_action.sns_topic_arn
  source-which-invoke-this-fn                          = module.create_lambda_for_cpu_utlization_alarm.function_name
  outcome-which-trigger-this-fn                        = var.outcome-to-trigger-create-cpu-credit-composite-alarm-fn
  source-notification-which-invoke-this-fn             = var.notification-from-create-cpu-utilization-alarm-fn
  logs-retention-days          = var.logs-retention-period
}

# This module deploys a lambda function which deletes all the alarms when an instance is terminated or it's class changes to non burstable type.
module "create_lambda_to_remove_cpu_credit_alarm" {
  source      = "./services/remove-cpu-credit-alarm"
  resource-id = "${var.remove-alarms-fn}-${var.deployment-id}"
  logs-retention-days          = var.logs-retention-period
}

#This module creates s3 bucket to store generated metric images.
module "s3_bucket_for_generated_metric_images" {
  source                               = "./common/s3/generated-metric-images"
  name-of-bucket-to-store-images       = "${var.part-name-of-s3-bucket-for-generated-cloudwatch-metric-images}-${var.deployment-id}"
  role-arn-of-generate-metric-image-fn = module.create_lambda_to_suppress_alarm_or_generate_metric_images.generate_metric_images_lambda_function_role_arn
}

# This module deploys a lambda function which sends out notifications to am email group.
module "create_lambda_to_send_composite_alarm_notification_to_email_group" {
  source                                                = "./services/post-alarm-state-to-email"
  resource-id                                           = "${var.send-composite-alarm-to-email-group-fn}-${var.deployment-id}"
  sns-topic-to-which-this-function-publish-notification = module.sns_topic_for_end_subscribers.sns_topic_arn
  lambda-layer-aws-powertools-and-more-arn              = module.aws_lamda_power_tools_layer_for_automated_cpu_credit_alarms.layer_arn
  ec2-event-bus-name                                    = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  event-rule-name-which-trigger-this-fn                 = module.create_lambda_to_suppress_alarm_or_generate_metric_images.post_alarm_state_notification_event_rule_name
  event-rule-arn-which-trigger-this-fn                  = module.create_lambda_to_suppress_alarm_or_generate_metric_images.post_alarm_state_notification_event_rule_arn
  logs-retention-days          = var.logs-retention-period
}


# This module deploys the lambda function which sends out notification to ms teams. 
module "create_lambda_to_send_composite_alarm_notification_to_ms_teams" {
  source                                   = "./services/post-alarm-state-to-ms-teams"
  resource-id                              = "${var.send-composite-alarm-to-ms-teams-fn}-${var.deployment-id}"
  ms-teams-web-hook-url                    = module.ssm_parameters_for_alarm_configuration.msteams_webhook_url_param_name
  lambda-layer-aws-powertools-and-more-arn = module.aws_lamda_power_tools_layer_for_automated_cpu_credit_alarms.layer_arn
  ec2-event-bus-name                       = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  event-rule-name-which-trigger-this-fn    = module.create_lambda_to_suppress_alarm_or_generate_metric_images.post_alarm_state_notification_event_rule_name
  event-rule-arn-which-trigger-this-fn     = module.create_lambda_to_suppress_alarm_or_generate_metric_images.post_alarm_state_notification_event_rule_arn
  logs-retention-days          = var.logs-retention-period
}


#This module deploys an api gateway which invokes the alarm suppression logic.
module "create_apigateway_to_post_cpu_credit_alarm_config_changes" {
  source      = "./services/post-cpu-credit-alarm-config-changes"
  resource-id = "${var.apigateway-suffix}-${var.deployment-id}"
}

#This module deploys lambda function which tags an ec2 instance to suppress the alarm notifications.
module "create_lambda_to_suppress_cpu_credit_balance_alarm" {
  source = "./services/suppress-cpu-credit-alarm"

  resource-id                  = "${var.suppress-alarms-prefix}-${var.deployment-id}"
  logs-retention-days          = var.logs-retention-period
  suppress-tag-name            = var.suppress-tag
  suppress-tag-value           = "true"
  api-gateway-id               = module.create_apigateway_to_post_cpu_credit_alarm_config_changes.api_gateway_id
  api-gateway-root-resource-id = module.create_apigateway_to_post_cpu_credit_alarm_config_changes.api_gateway_root_resource_id
  suppress-api-uri             = var.suppress-api-uri
}

# This module deploys a lambda function to suppress notification, generate metric images and create suppress api url.
module "create_lambda_to_suppress_alarm_or_generate_metric_images" {
  source                                                            = "./services/suppress-notification-or-generate-metric-images"
  suppress-tag-name                                                 = var.suppress-tag
  resource-id                                                       = "${var.suppress-notification-or-generate-metric-images-fn}-${var.deployment-id}"
  ec2-event-bus-name                                                = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  sns-topic-which-invoke-this-function                              = module.sns_topic_for_composite_alarm_action.sns_topic_arn
  suppress-api-endpoint                                             = "${module.create_lambda_to_suppress_cpu_credit_balance_alarm.api_url}/${var.suppress-api-uri}"
  lambda-layer-aws-powertools-and-more-arn                          = module.aws_lamda_power_tools_layer_for_automated_cpu_credit_alarms.layer_arn
  suppress-apigateway-host                                          = "${module.create_apigateway_to_post_cpu_credit_alarm_config_changes.api_gateway_id}.execute-api"
  suppress-api-uri                                                  = "/${module.create_lambda_to_suppress_cpu_credit_balance_alarm.stage_name}/${var.suppress-api-uri}"
  secret-name-which-store-access-key-and-secret-key-to-sign-api-url = "/rift/${var.deployment-id}/user/credentials"
  name-of-bucket-to-store-images                                    = module.s3_bucket_for_generated_metric_images.bucket_id
  outcome-of-this-fn-for-next-trigger                               = var.outcome-to-trigger-downstream-send-alarm-notification-fns
  notification-of-this-fn-for-next-trigger                          = var.notification-from-suppress-notification-or-generate-metric-images-fn
  logs-retention-days          = var.logs-retention-period
}

#This module deploys the SNS topic to triggers the downstream logic to create or update alarms for existing ec2.
module "sns_topic_to_create_or_update_alarms_for_existing_ec2" {
  source      = "./common/sns-topics/receive-notification-to-create-or-update-alarms-for-existing-ec2"
  resource-id = "${var.maintenance-operations-sns-topic}-${var.deployment-id}"
}

# This module deploys a lambda function creates or updates alarms for existing instances.
module "create_lambda_and_event_rule_to_create_or_update_alarms_for_existing_ec2" {
  source                                         = "./services/create-or-update-alarms-for-existing-instance"
  resource-id                                    = "${var.maintenance-operations-lambda-and-event-rule}-${var.deployment-id}"
  sns-topic-which-invoke-this-fn                 = module.sns_topic_to_create_or_update_alarms_for_existing_ec2.sns_topic_arn
  ec2-event-bus-name                             = module.event_bridge_bus_for_dynamic_ec2_monitor.main_bus_name
  arn-of-fn-which-is-invoked-by-this-event-rule  = module.create_lambda_for_cpu_credit_alarm.function_arn
  logs-retention-days                            = var.logs-retention-period
  create-alarm-notification                      = var.notification-to-create-alarms-for-existing-instance
  update-alarm-notification                      = var.notification-to-update-alarms
  update-operation                               = var.operation-type-to-update-alarm
  create-operation                               = var.operation-type-to-create-alarm
  name-of-fn-which-is-invoked-by-this-event-rule = module.create_lambda_for_cpu_credit_alarm.function_name
}
