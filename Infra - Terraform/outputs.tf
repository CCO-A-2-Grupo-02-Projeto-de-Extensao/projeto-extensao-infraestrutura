# Outputs da Infraestrutura

output "app_url" {
  description = "URL publica da aplicacao atraves do Load Balancer"
  value       = "http://${aws_lb.frontend.dns_name}"
}

output "alb_dns_name" {
  description = "DNS Name do Application Load Balancer"
  value       = aws_lb.frontend.dns_name
}

output "swagger_url" {
  description = "URL direta para a documentacao interativa Swagger da API"
  value       = "http://${aws_lb.frontend.dns_name}/swagger-ui/index.html"
}

output "cloudwatch_dashboard_url" {
  description = "Link direto para o painel de monitoramento no CloudWatch"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.arandu.dashboard_name}"
}

output "efs_id" {
  description = "ID do sistema de arquivos compartilhado EFS"
  value       = aws_efs_file_system.arandu.id
}

output "s3_bucket_name" {
  description = "Nome do bucket S3 criado para upload de documentos"
  value       = aws_s3_bucket.documentos.bucket
}

output "s3_bucket_bronze" {
  description = "Nome do bucket S3 da camada Bronze"
  value       = aws_s3_bucket.bronze.bucket
}

output "s3_bucket_silver" {
  description = "Nome do bucket S3 da camada Silver"
  value       = aws_s3_bucket.silver.bucket
}

output "s3_bucket_gold" {
  description = "Nome do bucket S3 da camada Gold"
  value       = aws_s3_bucket.gold.bucket
}

output "rds_endpoint" {
  description = "Endpoint de conexao com o banco MySQL RDS"
  value       = aws_db_instance.arandu.endpoint
}

output "rds_address" {
  description = "Host (IP/DNS) do banco RDS"
  value       = aws_db_instance.arandu.address
}

output "rds_database_name" {
  description = "Nome da base de dados"
  value       = aws_db_instance.arandu.db_name
}

output "rds_username" {
  description = "Usuario admin do RDS"
  value       = aws_db_instance.arandu.username
}

output "rds_password" {
  description = "Senha mestre gerada para o RDS MySQL"
  value       = local.rds_password
  sensitive   = true
}

output "jwt_secret" {
  description = "Chave secreta configurada no backend para validacao de tokens JWT"
  value       = local.jwt_secret
  sensitive   = true
}

output "frontend_1_public_ip" {
  description = "IP publico da instancia Frontend 1 (AZ 1a)"
  value       = aws_instance.frontend_1.public_ip
}

output "frontend_2_public_ip" {
  description = "IP publico da instancia Frontend 2 (AZ 1b)"
  value       = aws_instance.frontend_2.public_ip
}

output "backend_private_ip" {
  description = "IP privado da instancia Backend (AZ 1a)"
  value       = aws_instance.backend.private_ip
}

output "ssh_frontend_1" {
  description = "Comando para conectar via SSH no Frontend 1"
  value       = "ssh -i arandu-key.pem ubuntu@${aws_instance.frontend_1.public_ip}"
}

output "ssh_frontend_2" {
  description = "Comando para conectar via SSH no Frontend 2"
  value       = "ssh -i arandu-key.pem ubuntu@${aws_instance.frontend_2.public_ip}"
}
