variable "private_subnets" {}
variable "instance_sg" {}
variable "target_group_arn" {}

resource "aws_launch_template" "lt" {
  name_prefix   = "prod-lt"
  image_id      = "ami-0f5ee92e2d63afc18"
  instance_type = "t3.micro"

  vpc_security_group_ids = [var.instance_sg]

  user_data = base64encode(<<EOF
#!/bin/bash
yum update -y
yum install docker -y
systemctl start docker
docker run -d -p 80:80 nginx
EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 8
    }
  }
}

resource "aws_autoscaling_group" "asg" {
  desired_capacity    = 2
  min_size            = 2
  max_size            = 3
  vpc_zone_identifier = var.private_subnets

  target_group_arns = [var.target_group_arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}

output "asg_name" {
  value = aws_autoscaling_group.asg.name
}
