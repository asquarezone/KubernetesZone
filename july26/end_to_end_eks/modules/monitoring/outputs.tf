output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.node_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.node_memory.alarm_name,
    aws_cloudwatch_metric_alarm.failed_nodes.alarm_name,
    aws_cloudwatch_metric_alarm.crashloop.alarm_name,
  ]
}
