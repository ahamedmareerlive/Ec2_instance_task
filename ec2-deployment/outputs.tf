output "instance_ids" {

  value = {
    for k, v in aws_instance.linux_vm :
    k => v.id
  }
}

output "public_ips" {

  value = {
    for k, v in aws_instance.linux_vm :
    k => v.public_ip
  }
}


