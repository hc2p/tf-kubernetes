provider "aws" {
  region = "${var.region}"
}

module "vpc" {
  source              = "../modules/vpc"
  name                = "kubernetes"
  cidr                = "${var.vpc_cidr_block}"
  private_subnets     = "10.0.1.0/24,10.0.2.0/24"
  public_subnets      = "10.0.101.0/24,10.0.102.0/24"
  bastion_instance_id = "${aws_instance.bastion.id}"
  azs                 = "${var.availability_zones}"
}

# ssh keypair for instances
module "aws-ssh" {
  source = "../modules/ssh"
  public_key_file = "${var.public_key_file}"
  private_key_file = "${var.private_key_file}"
  region = "${var.region}"
  cluster_name = "${var.cluster_name}"
  default_instance_user  = "${var.default_instance_user}"
  master0_ip = "${aws_instance.master.0.private_ip}"
  master1_ip = "${aws_instance.master.1.private_ip}"
  worker0_ip = "${aws_instance.worker.0.private_ip}"
}

# security group to allow all traffic in and out of the instances in the VPC
module "sg-default" {
  source = "../modules/sg-traffic"

  vpc_id = "${module.vpc.vpc_id}"
}

module "route53" {
  source = "../modules/route53"
  vpc_id = "${module.vpc.vpc_id}"
  cluster_name = "${var.cluster_name}"
  environment = "${var.environment}"
}

module "elb" {
 source = "../modules/elb"

 security_groups = "${module.sg-default.security_group_id}"
 instances       = "${join(",", aws_instance.worker.*.id)}"
 subnets         = "${module.vpc.public_subnets}"
}

# Generate an etcd URL for the cluster
resource "template_file" "etcd_discovery_url" {
  template = "/dev/null"
  provisioner "local-exec" {
    command = "curl https://discovery.etcd.io/new?size=${var.masters} > ${var.etcd_discovery_url_file}"
  }
  # This will regenerate the discovery URL if the cluster size changes, we include the bastion here
  vars {
    size = "${var.masters}"
  }
}

# outputs
output "bastion.ip" {
  value = "${aws_eip.bastion.public_ip}"
}
output "master_ips" {
  value = "${join(",", aws_instance.master.*.private_ip)}"
}
output "worker_ips" {
  value = "${join(",", aws_instance.worker.*.private_ip)}"
}
output "vpc_cidr_block_ip" {
 value = "${module.vpc.vpc_cidr_block}"
}
output "elb.hostname" {
  value = "${module.elb.elb_dns_name}"
}
