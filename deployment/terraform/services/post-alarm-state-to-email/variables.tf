variable "resource-id" {
  description = "Name of the functionality/application."
}

variable "sns-topic-to-which-this-function-publish-notification" {
  description = "The SNS topic to send emails to the users."
}

variable "lambda-layer-aws-powertools-and-more-arn" {

}
variable "event-rule-name-which-trigger-this-fn" {

}

variable "event-rule-arn-which-trigger-this-fn" {

}

variable "ec2-event-bus-name" {

}


variable "logs-retention-days" {
  
}