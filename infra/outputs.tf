output "instance_public_ip" {
  description = "The public IP of the mirror worker"
  value       = aws_instance.mirror_worker.public_ip
}

output "instance_id" {
  value = aws_instance.mirror_worker.id
}