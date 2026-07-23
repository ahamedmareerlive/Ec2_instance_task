variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type = string
}

variable "key_name" {
  type    = string
  default = "terraform-linux-key"
}

variable "subnet_id" {
  type    = string
  default = "subnet-0165c54776802caf0"
}


variable "vm_count" {
  type    = number
  default = 1
}

