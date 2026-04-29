variable "vpc_id" {}
variable "public_subnets" {}
variable "alb_sg" {}

resource "aws_lb" "alb" {
  name               = "prod-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [var.alb_sg]
}

resource "aws_lb_target_group" "tg" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "REPLACE_WITH_ACM"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

output "target_group_arn" {
  value = aws_lb_target_group.tg.arn
}

output "alb_dns" {
  value = aws_lb.alb.dns_name
}
