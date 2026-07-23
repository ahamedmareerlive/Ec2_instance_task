data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "web_sg" {

  name        = "linux-web-sg"

  description = "Allow SSH and HTTP"

  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "linux-web-sg"
  }
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "pem" {
  filename        = "${path.module}/${var.key_name}.pem"
  content         = tls_private_key.generated.private_key_pem
  file_permission = "0400"
}

resource "aws_key_pair" "generated" {
  key_name   = var.key_name
  public_key = tls_private_key.generated.public_key_openssh

  tags = {
    Name = var.key_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {

  security_group_id = aws_security_group.web_sg.id

  ip_protocol = "tcp"

  from_port = 22

  to_port = 22

  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http" {

  security_group_id = aws_security_group.web_sg.id

  ip_protocol = "tcp"

  from_port = 80

  to_port = 80

  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all" {

  security_group_id = aws_security_group.web_sg.id

  ip_protocol = "-1"

  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_instance" "linux_vm" {

  for_each = var.instances

  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id = var.subnet_id

  key_name = aws_key_pair.generated.key_name

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  associate_public_ip_address = true

  user_data = file("${path.module}/userdata.sh")

  tags = {
    Name = each.value
  }
}

