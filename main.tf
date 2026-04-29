# -------------------------------
# VPC
# -------------------------------
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "prod-vpc"
  cidr   = "10.0.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]

  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

# -------------------------------
# Security Groups
# -------------------------------
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow inbound HTTP/HTTPS to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------------
# Application Load Balancer
  # Note: For this demo setup, the Application Load Balancer listens on HTTP (port 80) due to the absence of a valid SSL/TLS certificate in AWS Certificate Manager; in production, HTTPS (port 443) with a properly validated ACM certificate is required for secure communication.
# -------------------------------
resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


# -------------------------------
# IAM Role + Instance Profile
# -------------------------------
resource "aws_iam_role" "app_role" {
  name = "app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "app-profile"
  role = aws_iam_role.app_role.name
}

# -------------------------------
# Launch Template
# -------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-launch-template"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app_profile.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  network_interfaces {
    security_groups = [aws_security_group.app_sg.id]
    subnet_id       = module.vpc.private_subnets[0]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y
              systemctl enable nginx
              systemctl start nginx
              echo "Production App Running" > /usr/share/nginx/html/index.html

              # Install CloudWatch Logs agent
              yum install -y awslogs
              cat <<EOT > /etc/awslogs/awslogs.conf
              [general]
              state_file = /var/lib/awslogs/agent-state

              [/var/log/nginx/access.log]
              file = /var/log/nginx/access.log
              log_group_name = /aws/ec2/nginx
              log_stream_name = {instance_id}/access

              [/var/log/nginx/error.log]
              file = /var/log/nginx/error.log
              log_group_name = /aws/ec2/nginx
              log_stream_name = {instance_id}/error
              EOT

              systemctl enable awslogsd
              systemctl start awslogsd
              EOF
            )
}

# -------------------------------
# Auto Scaling Group
# -------------------------------
resource "aws_autoscaling_group" "app_asg" {
  name                = "app-asg"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 4
  vpc_zone_identifier = module.vpc.private_subnets

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  lb_target_group_arn   = aws_lb_target_group.app_tg.arn
}

# -------------------------------
# CloudWatch Alarms + SNS
# -------------------------------
resource "aws_sns_topic" "alerts" {
  name = "infra-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "This alarm triggers if CPU > 70% for 4 minutes"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
  alarm_actions   = [aws_sns_topic.alerts.arn]
  actions_enabled = true
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "UnhealthyHostsAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Triggers if ALB has more than 1 unhealthy host"
  dimensions = {
    TargetGroup  = aws_lb_target_group.app_tg.name
    LoadBalancer = aws_lb.app_alb.name
  }
  alarm_actions   = [aws_sns_topic.alerts.arn]
  actions_enabled = true
}

# -------------------------------
resource "aws_cloudwatch_dashboard" "infra_dashboard" {
  dashboard_name = "InfraDashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        "type" : "metric",
        "x" : 0,
        "y" : 0,
        "width" : 12,
        "height" : 6,
        "properties" : {
          "metrics" : [
            [ "AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app_asg.name ]
          ],
          "period" : 300,
          "stat" : "Average",
          "region" : "us-east-1",
          "title" : "EC2 CPU Utilization"
        }
      },
      {
        "type" : "metric",
        "x" : 12,
        "y" : 0,
        "width" : 12,
        "height" : 6,
        "properties" : {
          "metrics" : [
            [ "AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app_tg.name, "LoadBalancer", aws_lb.app_alb.name ]
          ],
          "period" : 60,
          "stat" : "Average",
          "region" : "us-east-1",
          "title" : "ALB Unhealthy Hosts"
        }
      }
    ]
  })
}
