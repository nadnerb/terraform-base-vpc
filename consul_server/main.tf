variable "name" {}
variable "environment" {}
variable "role_tag" {}
variable "environment_tag" {}
variable "costcenter_tag" {}
variable "stream_tag" {}
variable "key_name" {}
variable "ami" {}
variable "instance_type" {}
variable "region" {}
variable "subnet_id" {}
variable "security_groups" {}
variable "num_nodes" {}

resource "aws_instance" "consul" {

  instance_type = "${var.instance_type}"

  ami = "${var.ami}"
  subnet_id = "${var.subnet_id}"

  # This may be temporary
  associate_public_ip_address = "false"

  # Our Security groups
  security_groups = ["${split(",", replace(var.security_groups, "/,\s?$/", ""))}"]
  key_name = "${var.key_name}"

  # consul nodes in subnet
  count = "${var.num_nodes}"

  tags {
    Name = "consul_server_${var.environment}-${var.name}-${count.index+1}"
    Stream = "${var.stream_tag}"
    consul = "server"
    # required for ops reporting
    ServerRole = "${var.role_tag}"
    "Cost Center" = "${var.costcenter_tag}"
    Environment = "${var.environment_tag}"
  }

}
