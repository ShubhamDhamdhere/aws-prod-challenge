output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "lb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.app.dns_name
}

