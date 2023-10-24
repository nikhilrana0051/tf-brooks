# used to create an alarm per service per severity
# see: https://www.daveperrett.com/articles/2021/08/19/nested-for-each-with-terraform/
# we create a new map that is api_services x var.severities_to_create - a [sev1, 2, etc] alarm for each service  
locals {
  api_services = [
    {
      name         = "Pota API"
      log_name     = "PotaMS"
      action_group = "pota_api"
      web_home     = "https://con.t3.daimlertruck.com/display/DTNATELE/POTA+Microservice"
      runbook      = "https://con.t3.daimlertruck.com/display/DTNATELE/POTA+API+Microservice+Runbook"
      dashboard    = "https://azure-managed-grafana-c9ataeepb6hfe8cr.scus.grafana.azure.com/d/GYTG8Op4k/dota-microservice-law?orgId=1"
      tags         = merge(var.common_tags, { service_name = "skel-pota-api" })
    },
    {
      name         = "Fota API"
      log_name     = "FotaMS"
      action_group = "fota_api"
      web_home     = "https://con.t3.daimlertruck.com/display/DTNATELE/FOTA+Microservice"
      runbook      = "https://con.t3.daimlertruck.com/display/DTNATELE/FOTA+API+Microservice+Runbook"
      dashboard    = "https://azure-managed-grafana-c9ataeepb6hfe8cr.scus.grafana.azure.com/d/UToTHlF4k/fota-microservice-law?orgId=1"
      tags         = merge(var.common_tags, { service_name = "skel-fota-api" })
    },
    {
      name         = "Dota API"
      log_name     = "DotaMS"
      action_group = "fota_api"
      web_home     = "https://con.t3.daimlertruck.com/display/DTNATELE/DOTA+Microservice"
      runbook      = "https://con.t3.daimlertruck.com/display/DTNATELE/DOTA+API+Microservice+Runbook"
      dashboard    = "https://azure-managed-grafana-c9ataeepb6hfe8cr.scus.grafana.azure.com/d/UToTHlF4k/pota-microservice-law?orgId=1"
      tags         = merge(var.common_tags, { service_name = "skel-dota-api" })
    },
  ]

  service_with_severities = distinct(flatten([
    for service in local.api_services : [
      for sev in var.severities_to_create : {
        name         = service.name
        web_home     = service.web_home
        runbook      = service.runbook
        log_name     = service.log_name
        action_group = service.action_group
        tags         = service.tags
        dashboard    = service.dashboard
        severity     = sev
        prefix       = "[${var.alarm_prefix.stage}-Sev${sev}]"
      }
    ]
  ]))

  action_group_params = { for kk, vv in var.action_group_params : kk => vv if endswith(kk, "_api") }

  # [Sev0, Sev1, Sev2, Sev3] - see usages of "element(local.uptime_thresholds"
  response_thresholds     = [0, 0, 1000, 2000] # milliseconds to quantify "slow" calls
  success_thresholds      = [0, 0, 95, 97]     # success percentages
  unauthorized_thresholds = [0, 0, 30, 15]     # count of failed login/access attempts
  uptime_thresholds       = [0, 0, 40, 50]     # count of pings/minute (should be 60)
}

# TODO: refactor so we're using "service name", then it can be a tag below
resource "azurerm_monitor_action_group" "skel_pager_duty_api" {
  for_each = local.action_group_params

  provider            = azurerm.spoke
  name                = each.value.name
  short_name          = each.value.name
  resource_group_name = var.azurerm_resource_group_name
  tags                = var.common_tags

  webhook_receiver {
    name                    = each.value.name
    service_uri             = each.value.url
    use_common_alert_schema = true
  }
}


#
# TODO - DRY this up - lots of stuff is the same between alarms, almost all of it if a function took params
# 1. I think I'd have to parameterize all the things inside each alarm.  It would be a little DRY'r but less readale
#
# Is one way to "fix this" we use for_each and load this resource as a module?  But then we'd need to parameterize the name...  won't work?

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "response-time" {
  # see: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2#arguments-reference
  for_each = { for service in local.service_with_severities : "${service.name}.${service.severity}" => service if contains([1, 3], service.severity) }

  provider            = azurerm.spoke
  name                = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Response-Time"
  display_name        = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Response-Time"
  severity            = each.value.severity
  location            = var.location
  resource_group_name = var.azurerm_resource_group_name
  scopes              = [var.source_azure_log_analytics_workspace_id]
  tags                = each.value.tags
  enabled             = contains([3], each.value.severity) ? var.enable_alarms : false

  description = <<-DESC
  TODO
  Runbook:   ${each.value.runbook}
  Dashboard: ${each.value.dashboard}
  Web Home:  ${each.value.web_home}
  DESC

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  # misc items
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  skip_query_validation            = true

  action {
    action_groups = concat(
      [azurerm_monitor_action_group.skel_pager_duty_api[each.value.action_group].id],           # one above
      [for kk, vv in var.action_groups : vv.id if contains(vv.severities, each.value.severity)] # existing ones passed in
    )
    custom_properties = { # TODO - not sure this will work, or needed...
      email_subject          = "${each.value.name} Response Time"
      custom_webhook_payload = "{}"
    }
  }

  criteria {
    query = <<-QUERY
    ApiRequests_CL
    | where serviceName_s == "${each.value.log_name}" and not(path_s == "/ping")
    QUERY

    time_aggregation_method = "Average"
    threshold               = element(local.success_thresholds, each.value.severity)
    operator                = "GreaterThan"
    metric_measure_column   = "responseTime_d"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 3
      number_of_evaluation_periods             = 3
    }
  }
}



# success-rate
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "success-rate" {
  # see: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2#arguments-reference
  for_each = { for service in local.service_with_severities : "${service.name}.${service.severity}" => service if contains([1, 3], service.severity) }

  provider            = azurerm.spoke
  name                = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Success-Rate"
  display_name        = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Success-Rate"
  severity            = each.value.severity
  location            = var.location
  resource_group_name = var.azurerm_resource_group_name
  scopes              = [var.source_azure_log_analytics_workspace_id]
  tags                = each.value.tags
  enabled             = contains([3], each.value.severity) ? var.enable_alarms : false

  description = <<-DESC
  TODO
  
  Runbook:   ${each.value.runbook}
  Dashboard: ${each.value.dashboard}
  Web Home:  ${each.value.web_home}
  DESC

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  # misc items
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  skip_query_validation            = true

  action {
    action_groups = concat(
      [azurerm_monitor_action_group.skel_pager_duty_api[each.value.action_group].id],           # one above
      [for kk, vv in var.action_groups : vv.id if contains(vv.severities, each.value.severity)] # existing ones passed in
    )
    custom_properties = { # TODO - not sure this will work, or needed...
      email_subject          = "${each.value.name} Success Rate"
      custom_webhook_payload = "{}"
    }
  }

  criteria {
    query = <<-QUERY
      ApiRequests_CL
      | where serviceName_s == "${each.value.log_name}"
      | extend result = iff(httpStatus_d < 500, "success", "failure")
      | summarize counter = count() by result
      | extend bag = bag_pack(result, todecimal(counter))
      | summarize obj_json = make_bag(bag)
      | evaluate bag_unpack(obj_json)
      | extend failure = column_ifexists('failure', 0)
      | extend success = column_ifexists('success', 0)
      | extend rate = toint((success / (success + failure) * 100))
      QUERY

    time_aggregation_method = "Average"
    threshold               = element(local.success_thresholds, each.value.severity)
    operator                = "LessThan"
    metric_measure_column   = "rate"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
}


# success-rate
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "unauthorized-count" {
  # see: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2#arguments-reference
  for_each = { for service in local.service_with_severities : "${service.name}.${service.severity}" => service if contains([1, 3], service.severity) }

  provider            = azurerm.spoke
  name                = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Unauthorized-Count"
  display_name        = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Unauthorized-Count"
  severity            = each.value.severity
  location            = var.location
  resource_group_name = var.azurerm_resource_group_name
  scopes              = [var.source_azure_log_analytics_workspace_id]
  tags                = each.value.tags
  enabled             = contains([3], each.value.severity) ? var.enable_alarms : false

  description = <<-DESC
  TODO
  
  Runbook:   ${each.value.runbook}
  Dashboard: ${each.value.dashboard}
  Web Home:  ${each.value.web_home}  
  DESC

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  # misc items
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  skip_query_validation            = true

  action {
    action_groups = concat(
      [azurerm_monitor_action_group.skel_pager_duty_api[each.value.action_group].id],           # one above
      [for kk, vv in var.action_groups : vv.id if contains(vv.severities, each.value.severity)] # existing ones passed in
    )
    custom_properties = { # TODO - not sure this will work, or needed...
      email_subject          = "${each.value.name} Unauthorized Count"
      custom_webhook_payload = "{}"
    }
  }

  criteria {
    query = <<-QUERY
      ApiRequests_CL
      | where serviceName_s == "${each.value.log_name}" and httpStatus_d in (401, 403)
      | count
      QUERY

    time_aggregation_method = "Total"
    threshold               = element(local.success_thresholds, each.value.severity)
    operator                = "GreaterThan"
    metric_measure_column   = "Count"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
}

# success-rate
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "uptime-ping" {
  # see: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2#arguments-reference
  for_each = { for service in local.service_with_severities : "${service.name}.${service.severity}" => service if contains([1, 3], service.severity) }

  provider            = azurerm.spoke
  name                = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Uptime-Ping"
  display_name        = "${each.value.prefix}${replace(each.value.name, " ", "-")}-Uptime-Ping"
  severity            = each.value.severity
  location            = var.location
  resource_group_name = var.azurerm_resource_group_name
  scopes              = [var.source_azure_log_analytics_workspace_id]
  tags                = each.value.tags
  enabled             = contains([3], each.value.severity) ? var.enable_alarms : false

  description = <<-DESC
  TODO
  
  Runbook:   ${each.value.runbook}
  Dashboard: ${each.value.dashboard}
  Web Home:  ${each.value.web_home}
  DESC

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  # misc items
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  skip_query_validation            = true

  action {
    action_groups = concat(
      [azurerm_monitor_action_group.skel_pager_duty_api[each.value.action_group].id],           # one above
      [for kk, vv in var.action_groups : vv.id if contains(vv.severities, each.value.severity)] # existing ones passed in
    )
    custom_properties = { # TODO - not sure this will work, or needed...
      email_subject          = "${each.value.name} Uptime Ping"
      custom_webhook_payload = "{}"
    }
  }

  criteria {
    query = <<-QUERY
      ApiRequests_CL
      | where serviceName_s == "${each.value.log_name}" and httpStatus_d < 500 and path_s == "/ping"
      | count
      QUERY

    time_aggregation_method = "Total"
    threshold               = element(local.success_thresholds, each.value.severity)
    operator                = "LessThan"
    metric_measure_column   = "Count"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
}
