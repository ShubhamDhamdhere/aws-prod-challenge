variable "asg_name" {}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  threshold           = 80
  statistic           = "Average"
}
