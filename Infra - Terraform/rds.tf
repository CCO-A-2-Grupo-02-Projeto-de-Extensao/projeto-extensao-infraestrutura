# Banco de Dados Relacional: RDS MySQL

# Gerador automatico de senha caso o usuario nao informe no tfvars
resource "random_password" "rds" {
  length  = 16
  special = false
}

# Gerador da chave JWT usada pelo Spring Security
resource "random_password" "jwt" {
  length  = 32
  special = false
}

locals {
  rds_password = var.rds_password != null ? var.rds_password : random_password.rds.result
  jwt_secret   = var.jwt_secret != null ? var.jwt_secret : random_password.jwt.result
}

# Grupo de subnets em diferentes AZs para o banco
resource "aws_db_subnet_group" "arandu" {
  name        = "rds-subnet-group-arandu"
  description = "Subnet group do RDS Arandu"
  subnet_ids = [
    aws_subnet.subnets["db_1"].id,
    aws_subnet.subnets["db_2"].id
  ]

  tags = {
    Name = "rds-subnet-group-arandu"
  }
}

# Instancia RDS MySQL 8.0
resource "aws_db_instance" "arandu" {
  identifier             = var.rds_instance_id
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.rds_class
  allocated_storage      = var.rds_allocated_storage
  storage_type           = "gp2"
  db_name                = var.rds_db_name
  username               = var.rds_username
  password               = local.rds_password
  db_subnet_group_name   = aws_db_subnet_group.arandu.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  backup_retention_period = 0
  multi_az               = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = var.rds_instance_id
  }
}
