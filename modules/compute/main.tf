# EC2 SG (only ALB access)
resource "aws_security_group" "ec2_sg" {
  vpc_id = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch Template
resource "aws_launch_template" "lt" {
  image_id      = "ami-0f58b397bc5c1f2e8"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = false
    security_groups = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(<<EOF
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker

docker run -d -p 80:80 nginx
EOF
  )
}

# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  vpc_zone_identifier = var.private_subnets

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  target_group_arns = [var.target_group_arn]

  health_check_type = "ELB"
}
