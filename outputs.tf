output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_dns" {
  value = module.alb.alb_dns_name
}

output "asg_name" {
  value = module.asg.asg_name
}
