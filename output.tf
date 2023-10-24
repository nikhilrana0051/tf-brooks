output "all_one_dimension_names" {
  description = "All One Dimension alert names."
  value = toset(concat(
    [for ii in azurerm_monitor_scheduled_query_rules_alert_v2.test-alert-one : ii.name],
  ))
}

output "all_two_dimension_alert_names" {
  description = "All Ingress alert names."
  value = toset(concat(
    [for ii in azurerm_monitor_scheduled_query_rules_alert_v2.response-time : ii.name],
    [for ii in azurerm_monitor_scheduled_query_rules_alert_v2.success-rate : ii.name],
    [for ii in azurerm_monitor_scheduled_query_rules_alert_v2.unauthorized-count : ii.name],
    [for ii in azurerm_monitor_scheduled_query_rules_alert_v2.uptime-ping : ii.name],
  ))
}
