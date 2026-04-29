module "vpc" {
  source = "./modules/vpc"
}

module "security" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id
}

module "alb" {
  source         = "./modules/alb"
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnets
  alb_sg         = module.security.alb_sg
}

module "asg" {
  source           = "./modules/asg"
  private_subnets  = module.vpc.private_subnets
  instance_sg      = module.security.ec2_sg
  target_group_arn = module.alb.target_group_arn
}

module "monitoring" {
  source   = "./modules/monitoring"
  asg_name = module.asg.asg_name
}

module "budget" {
  source = "./modules/budget"
}
