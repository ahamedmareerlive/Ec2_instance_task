variable "aws_region" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instances" {
  type = map(string)

  default = {
    vm01 = "Linux-VM-01"
    vm02 = "Linux-VM-02"
  }
}
