data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "selected" {
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

locals {
  is_windows = data.aws_ami.selected.platform == "windows"
  user_data  = local.is_windows ? file("${path.module}/userdata.ps1") : file("${path.module}/userdata.sh")
}

resource "aws_security_group" "web_sg" {
  name        = "vm-sg"
  description = "Allow SSH, RDP and HTTP"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "vm-sg"
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
  count             = local.is_windows ? 0 : 1
  security_group_id = aws_security_group.web_sg.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "rdp" {
  count             = local.is_windows ? 1 : 0
  security_group_id = aws_security_group.web_sg.id
  ip_protocol       = "tcp"
  from_port         = 3389
  to_port           = 3389
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web_sg.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "vm" {
  count         = var.vm_count
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  key_name      = aws_key_pair.generated.key_name

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  associate_public_ip_address = true
  user_data                   = local.user_data

  tags = {
    Name = "${local.is_windows ? "Windows" : "Linux"}-VM-${count.index + 1}"
  }
}


