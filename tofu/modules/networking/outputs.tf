output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "eip_allocation_id" {
  value = aws_eip.main.id
}

output "public_ip" {
  value = aws_eip.main.public_ip
}
