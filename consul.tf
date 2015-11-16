#############################################################################
# Consul servers
##############################################################################
resource "aws_security_group" "consul_server" {
  name = "${var.consul_security_group_name}"
  description = "Consul server, UI and maintenance."
  vpc_id = "${var.vpc_id}"

  // These are for maintenance
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // consul ui
  ingress {
    from_port = 8500
    to_port = 8500
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "consul server security group"
    stream = "${var.stream_tag}"
  }
}

resource "aws_security_group" "consul_agent" {
  name = "consul agent"
  description = "Consul agents internal traffic."
  vpc_id = "${var.vpc_id}"

  // These are for internal traffic
  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    self = true
  }

  ingress {
    from_port = 0
    to_port = 65535
    protocol = "udp"
    self = true
  }

  tags {
    Name = "consul agent security group"
    stream = "${var.stream_tag}"
    # required for ops reporting
    ServerRole = "${var.role_tag}"
    "Cost Center" = "${var.costcenter_tag}"
    Environment = "${var.environment_tag}"
  }
}

module "consul_servers_a" {
  source = "./consul_server"

  name = "a"
  region = "${var.aws_region}"
  ami = "${lookup(var.consul_amis, var.aws_region)}"
  instance_type = "${var.consul_instance_type}"
  subnet_id = "${aws_subnet.public_a.id}"
  num_nodes = "${var.consul_num_nodes_subnet_a}"
  security_groups = "${concat(aws_security_group.consul_server.id, ",", aws_security_group.consul_agent.id, ",", var.additional_security_groups)}"
  key_name = "${var.key_name}"
  key_path = "${var.key_path}"
  stream_tag = "${var.stream_tag}"
  role_tag = "${var.consul_role_tag}"
  costcenter_tag = "${var.costcenter_tag}"
  environment_tag = "${var.environment_tag}"
}

module "consul_servers_b" {
  source = "./consul_server"

  name = "b"
  region = "${var.aws_region}"
  ami = "${lookup(var.consul_amis, var.aws_region)}"
  instance_type = "${var.consul_instance_type}"
  subnet_id = "${aws_subnet.public_b.id}"
  num_nodes = "${var.consul_num_nodes_subnet_b}"
  security_groups = "${concat(aws_security_group.consul_server.id, ",", aws_security_group.consul_agent.id, ",", var.additional_security_groups)}"
  key_name = "${var.key_name}"
  key_path = "${var.key_path}"
  stream_tag = "${var.stream_tag}"
  role_tag = "${var.consul_role_tag}"
  costcenter_tag = "${var.costcenter_tag}"
  environment_tag = "${var.environment_tag}"
}

resource "aws_security_group" "consul_elb" {
  name = "consul elb"
  description = "http and https ports mapped to consul"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["${var.external_cidr_blocks}"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["${var.external_cidr_blocks}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "consul elb security group"
    stream = "${var.stream_tag}"
  }
}

resource "aws_elb" "consul" {
  name = "consul-elb"
  security_groups = ["${aws_security_group.consul_elb.id}"]
  subnets = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]

  listener {
    instance_port = 8500
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  listener {
    instance_port = 8500
    instance_protocol = "http"
    lb_port = 443
    lb_protocol = "https"
    ssl_certificate_id = "${var.ssl_certificate_arn}"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 3
    timeout = 10
    target = "TCP:8500"
    interval = 30
  }

  instances = ["${split(",", module.consul_servers_a.ids)}", "${split(",", module.consul_servers_b.ids)}"]
  cross_zone_load_balancing = true
  idle_timeout = 400
  connection_draining = true
  connection_draining_timeout = 400
  internal = false

  tags {
    Name = "consul elb"
    ServerRole = "${var.role_tag} elb"
    CostCenter = "${var.costcenter_tag}"
    Environment = "${var.environment_tag}"
    Stream = "${var.stream_tag}"
  }
}

##############################################################################
# Route 53
##############################################################################

resource "aws_route53_record" "consul_private" {
  zone_id = "${aws_route53_zone.private_zone.id}"
  name = "${var.private_hosted_zone_name}"
  type = "A"
  ttl = "30"
  records = ["${split(",", module.consul_servers_a.private-ips)}", "${split(",", module.consul_servers_b.private-ips)}"]
}

resource "aws_route53_record" "consul_elb_private" {
  zone_id = "${aws_route53_zone.private_zone.zone_id}"
  name = "private.${var.consul_public_hosted_zone_name}"
  type = "A"

  alias {
    name = "${aws_elb.consul.dns_name}"
    zone_id = "${aws_elb.consul.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "consul_public" {
  zone_id = "${var.public_hosted_zone_id}"
  name = "${var.consul_public_hosted_zone_name}"
  type = "A"

  alias {
    name = "${aws_elb.consul.dns_name}"
    zone_id = "${aws_elb.consul.zone_id}"
    evaluate_target_health = true
  }
}
