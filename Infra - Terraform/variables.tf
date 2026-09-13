variable "aws_region" {
  description = "Regiao da AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "dev"
}

variable "vpc_name" {
  description = "Nome da VPC"
  type        = string
  default     = "vpc-arandu"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets_config" {
  description = "Mapeamento das subnets"
  type = map(object({
    cidr                    = string
    az                      = string
    map_public_ip_on_launch = bool
    name                    = string
  }))
  default = {
    frontend_1 = {
      cidr                    = "10.0.1.0/24"
      az                      = "us-east-1a"
      map_public_ip_on_launch = true
      name                    = "subnet-frontend-publica-arandu"
    }
    frontend_2 = {
      cidr                    = "10.0.4.0/24"
      az                      = "us-east-1b"
      map_public_ip_on_launch = true
      name                    = "subnet-frontend-publica-arandu-2"
    }
    backend = {
      cidr                    = "10.0.2.0/24"
      az                      = "us-east-1a"
      map_public_ip_on_launch = false
      name                    = "subnet-backend-privada-arandu"
    }
    db_1 = {
      cidr                    = "10.0.3.0/24"
      az                      = "us-east-1a"
      map_public_ip_on_launch = false
      name                    = "subnet-privada-db-arandu"
    }
    db_2 = {
      cidr                    = "10.0.5.0/24"
      az                      = "us-east-1b"
      map_public_ip_on_launch = false
      name                    = "subnet-privada-db-arandu-2"
    }
  }
}

variable "key_name" {
  description = "Nome do par de chaves SSH"
  type        = string
  default     = "arandu-key"
}

variable "instance_type" {
  description = "Tipo das instancias EC2"
  type        = string
  default     = "t3.micro"
}

variable "ami_owner" {
  description = "Owner ID da AMI Canonical Ubuntu"
  type        = string
  default     = "099720109477"
}

variable "ami_filter" {
  description = "Filtro da AMI Ubuntu"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "frontend_docker_image" {
  description = "Imagem Docker do Frontend"
  type        = string
  default     = "pedrobarbosa996/arandu_digital:frontend"
}

variable "backend_docker_image" {
  description = "Imagem Docker do Backend"
  type        = string
  default     = "pedrobarbosa996/arandu_digital:backend"
}

variable "alb_name" {
  description = "Nome do ALB"
  type        = string
  default     = "alb-arandu-frontend"
}

variable "tg_frontend_name" {
  description = "Nome do Target Group do Frontend"
  type        = string
  default     = "tg-arandu-frontend"
}

variable "tg_backend_name" {
  description = "Nome do Target Group do Backend"
  type        = string
  default     = "tg-arandu-backend"
}

variable "efs_name" {
  description = "Nome do EFS"
  type        = string
  default     = "efs-arandu"
}

variable "s3_member_tag" {
  description = "Tag de membro para sufixo do S3"
  type        = string
  default     = "pedro"
}

variable "bucket_bronze_name" {
  description = "Nome do bucket bronze"
  type        = string
  default     = null
}

variable "bucket_silver_name" {
  description = "Nome do bucket silver"
  type        = string
  default     = null
}

variable "bucket_gold_name" {
  description = "Nome do bucket gold"
  type        = string
  default     = null
}

variable "rds_instance_id" {
  description = "Identificador da instancia RDS"
  type        = string
  default     = "rds-arandu-db"
}

variable "rds_db_name" {
  description = "Nome do schema do banco"
  type        = string
  default     = "bdClubeDesbravadores"
}

variable "rds_username" {
  description = "Usuario admin do banco"
  type        = string
  default     = "admin"
}

variable "rds_password" {
  description = "Senha do banco"
  type        = string
  default     = null
  sensitive   = true
}

variable "rds_class" {
  description = "Classe da instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Armazenamento em GB do RDS"
  type        = number
  default     = 20
}

variable "sql_url" {
  description = "URL do script SQL inicial"
  type        = string
  default     = "https://raw.githubusercontent.com/CCO-A-2-Grupo-02-Projeto-de-Extensao/projeto-extensao-backend/main/bdClubeDesbravadores.sql"
}

variable "jwt_secret" {
  description = "Chave secreta JWT"
  type        = string
  default     = null
  sensitive   = true
}

variable "use_lab_instance_profile" {
  description = "Usar LabInstanceProfile da AWS Academy"
  type        = bool
  default     = true
}
