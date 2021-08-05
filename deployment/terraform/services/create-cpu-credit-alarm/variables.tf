variable "resource-id" {
  description = "Name of the functionality/application"
}

variable "period" {
  description = "Metric evaluation period"
}

variable "datapoints" {
  description = "Datapoints to trigger alarm"
}

variable "evaluation-periods" {
  description = "Number of evalaution periods"
}

variable "threshold" {
  description = "Threshold to breach for alarm to trigger"
}

variable "additional-datapoints" {
  description = "Datapoints to trigger alarm for cpu intensive applications."
}

variable "additional-evaluation-periods" {
  description = "Number of evalaution periods for cpu intensive applications."
}

variable "compute-intensive-workloads-regix-list" {
  description = "list of regix pattern of compute intensive workloads."
}

variable "ec2-event-bus-name" {

}

variable "outcome-which-trigger-this-fn" {

}

variable "source-which-invoke-this-fn" {

}

variable "outcome-of-this-fn-for-next-trigger" {

}

variable "source-notification-which-invoke-this-fn" {

}

variable "notification-of-this-fn-for-next-trigger" {

}

variable "logs-retention-days" {
  
}