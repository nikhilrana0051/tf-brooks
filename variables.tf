variable "location" {}

variable "alarm_prefix" {}

variable "common_tags" {}

variable "enable_alarms" {}

variable "action_groups" {
  description = "Merge collection of existing and shared action groups and the severities to apply each."
  type = map(object({
    severities = list(number)
    name       = string
    id         = string
  }))
  default = null
}

variable "severities_to_create" {}

variable "source_azure_log_analytics_workspace_name" {}

variable "source_azure_log_analytics_workspace_id" {}


### From Shared Module ###

variable "azurerm_resource_group_name" {
  description = "RG where the resources will be created."
  type        = string
}


### Hard-coded variables (not over-rideable) ###

variable "action_group_params" {
  description = "Parameters passed into the Action Groups created inside this module.  These are links to PagerDuty Prod (there is only one) and are real services that shouldn't change."
  type        = map(object({ name = string, email = string, url = string }))
  default = {
    # NOTE: uses '_api' to match with alert groups in `api.tf`
    # TODO - this is a little gross inside api.tf now
    fota_api = {
      name  = "FOTA MS PD"
      email = "some.one@daimlertruck.com"
      url   = "https://events.pagerduty.com/integration/123455/enqueue"
    }
    dota_api = {
      name  = "DOTA MS PD"
      email = "some.one@daimlertruck.com"
      url   = "https://events.pagerduty.com/integration/123456/enqueue"
    }
    pota_api = {
      name  = "POTA MS PD"
      email = "some.one@daimlertruck.com"
      url   = "https://events.pagerduty.com/integration/123457/enqueue"
    }
    ingress = {
      name  = "OTAIngressPD" # 12 character limit
      email = "some.one@daimlertruck.com"
      url   = "https://events.pagerduty.com/integration/123458/enqueue"
    }
    egress = {
      name  = "OTAEgressPD"
      email = "some.one@daimlertruck.com"
      url   = "https://events.pagerduty.com/integration/123459/enqueue"
    }
  }
}

###                                                                                ###
### Azure variables (Note: not located in tfvars, provided by deployment pipeline) ###
###                                                                                ###

variable "client_id" {
  type = string
}
variable "client_secret" {
  type = string
}
variable "tenant_id" {
  type = string
}
variable "spoke_subscription_id" {
  type = string
}
