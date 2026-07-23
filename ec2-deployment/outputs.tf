output "instance_ids" {
  value = aws_instance.vm[*].id
}

output "public_ips" {
  value = aws_instance.vm[*].public_ip
}



