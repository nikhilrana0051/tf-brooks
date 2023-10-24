locals {
  engress_tags = merge(var.common_tags, {
    service_name = "skel-ota-egress"
  })

  data_by_severtity_egress = distinct(flatten([
    for sev in var.severities_to_create : {
      severity = sev
      prefix   = "[${var.alarm_prefix.stage}-Sev${sev}]"
    }
    ]
  ))

  runbook_egress   = "https://con.t3.daimlertruck.com/display/DTNATELE/Team4+OTA+Ingest%2C+Operations+and+Flink+Runbook_egress"
  web_home_egress  = "https://con.t3.daimlertruck.com/display/DTNATELE/OTA+Ingest+Service+and+Operation+Framework"
  dashboard_egress = "https://azure-managed-grafana-c9ataeepb6hfe8cr.scus.grafana.azure.com/d/RTN7CEcGz/ota-operation-detroit-fota-web-service-calls"

  action_group_params_egress = var.action_group_params.egress

  # [Sev0, Sev1, Sev2...] - see usages of "element(local.XXXX_thresholds"
  egress_reservoir_call_thresholds = [0, 10, 20, 40]
}

# spoke provider for creating alerts/resources
provider "azurerm" {
  alias = "spoke"
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.spoke_subscription_id
}

resource "azurerm_monitor_action_group" "skel_pager_duty_egress" {
  provider            = azurerm.spoke
  name                = local.action_group_params_egress.name
  short_name          = local.action_group_params_egress.name
  resource_group_name = var.azurerm_resource_group_name
  tags                = var.common_tags

  webhook_receiver {
    name                    = local.action_group_params_egress.name
    service_uri             = local.action_group_params_egress.url
    use_common_alert_schema = true
  }
}


resource "azurerm_monitor_scheduled_query_rules_alert_v2" "test-alert-one" {
  for_each = { for sev in local.data_by_severtity_egress : sev.prefix => sev if contains([1, 3], sev.severity) }

  provider            = azurerm.spoke
  name                = "${each.value.prefix}Egress-Reservoir-Calls"
  display_name        = "${each.value.prefix}Egress-Reservoir-Calls"
  severity            = each.value.severity
  location            = var.location
  resource_group_name = var.azurerm_resource_group_name
  scopes              = [var.source_azure_log_analytics_workspace_id]
  tags                = local.engress_tags
  enabled             = false # var.enable_alarms

  description = <<-DESC
  Calls to Reservoir while creating FOTA tasks are in a degraded state.  See "GetPowertrainCompatResponse" response types in Dashboard.
  Runbook:   ${local.runbook_egress}
  Dashboard: ${local.dashboard_egress}
  Web Home:  ${local.web_home_egress}
  DESC

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  # misc items
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  skip_query_validation            = true

  action {
    action_groups = concat(
      [azurerm_monitor_action_group.skel_pager_duty_egress.id],                                 # Created above
      [for kk, vv in var.action_groups : vv.id if contains(vv.severities, each.value.severity)] # Groups passed in
    )
    custom_properties = { # TODO - not sure this will work, or needed...
      email_subject          = "Egress Reservoir Calls"
      custom_webhook_payload = "{}"
    }
  }

  # TOOD: this won't work - there is no traffic.  tweak this alarm into something helpful.
  # we need to understand what erros look like and detect them.
  # i don't think we can calculate successs rate with the data at hand
  criteria {
    query = <<-QUERY
      FotaWebServiceMonitor_CL 
      | where type_s == "GetPowertrainCompatResponse"
      | count
    QUERY

    time_aggregation_method = "Total"
    threshold               = element(local.egress_reservoir_call_thresholds, each.value.severity)
    operator                = "LessThan"
    metric_measure_column   = "Count"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
}
