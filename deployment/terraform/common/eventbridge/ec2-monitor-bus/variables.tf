variable "resource-id" {
  description = "Lambda functions which send out notifications to users need to subscribe to this SNS topic. This SNS topic is set as an action to the Composite Alarm. It is used by the services module."
}
