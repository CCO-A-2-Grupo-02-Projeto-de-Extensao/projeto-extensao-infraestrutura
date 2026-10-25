output "app_url" {
  value = "http://${aws_lb.frontend.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.frontend.dns_name
}

output "swagger_url" {
  value = "http://${aws_lb.frontend.dns_name}/swagger-ui/index.html"
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.arandu.dashboard_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.arandu.repository_url
}

output "efs_id" {
  value = aws_efs_file_system.arandu.id
}

output "s3_bucket_name" {
  description = "Nome do bucket S3 criado para upload de documentos"
  value       = local.bucket_documentos_name
}

output "s3_bucket_bronze" {
  description = "Nome do bucket S3 da camada Bronze"
  value       = local.bucket_bronze_name
}

output "s3_bucket_silver" {
  description = "Nome do bucket S3 da camada Silver"
  value       = local.bucket_silver_name
}

output "s3_bucket_gold" {
  description = "Nome do bucket S3 da camada Gold"
  value       = local.bucket_gold_name
}

output "rds_endpoint" {
  value = aws_db_instance.arandu.endpoint
}

output "rds_address" {
  value = aws_db_instance.arandu.address
}

output "rds_database_name" {
  value = aws_db_instance.arandu.db_name
}

output "rds_username" {
  value = aws_db_instance.arandu.username
}

output "rds_password" {
  value     = local.rds_password
  sensitive = true
}

output "jwt_secret" {
  value     = local.jwt_secret
  sensitive = true
}

output "frontend_1_public_ip" {
  value = aws_instance.frontend_1.public_ip
}

output "frontend_2_public_ip" {
  value = aws_instance.frontend_2.public_ip
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}

output "ssh_frontend_1" {
  value = "ssh -i arandu-key.pem ubuntu@${aws_instance.frontend_1.public_ip}"
}

output "ssh_frontend_2" {
  value = "ssh -i arandu-key.pem ubuntu@${aws_instance.frontend_2.public_ip}"
}
