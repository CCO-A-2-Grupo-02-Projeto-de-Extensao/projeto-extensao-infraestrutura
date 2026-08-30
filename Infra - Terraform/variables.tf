# Variaveis globais e de infraestrutura

variable "aws_region" {
  description = "Regiao da AWS onde a infraestrutura sera provisionada"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Identificador do ambiente"
  type        = string
  default     = "dev"
}

# Rede (VPC e Subnets)
variable "vpc_name" {
  description = "Nome identificador da VPC"
  type        = string
  default     = "vpc-arandu"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Subnets mapeadas exatamente como no shell script
variable "subnets_config" {
  description = "Mapeamento das subnets publicas e privadas"
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

# Computacao e Instancias EC2
variable "key_name" {
  description = "Nome do par de chaves SSH"
  type        = string
  default     = "arandu-key"
}

variable "instance_type" {
  description = "Tipo das instancias EC2 para frontend e backend"
  type        = string
  default     = "t3.micro"
}

variable "ami_owner" {
  description = "ID do proprietario da AMI oficial da Canonical/Ubuntu"
  type        = string
  default     = "099720109477"
}

variable "ami_filter" {
  description = "Filtro de busca da AMI Ubuntu Jammy 22.04 LTS"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "frontend_docker_image" {
  description = "Imagem Docker do Frontend (Nginx)"
  type        = string
  default     = "pedrobarbosa996/arandu_digital:frontend"
}

variable "backend_docker_image" {
  description = "Imagem Docker do Backend (Spring Boot)"
  type        = string
  default     = "pedrobarbosa996/arandu_digital:backend"
}

# Balanceador de Carga (ALB)
variable "alb_name" {
  description = "Nome do Application Load Balancer"
  type        = string
  default     = "alb-arandu-frontend"
}

variable "tg_frontend_name" {
  description = "Nome do Target Group para os Frontends"
  type        = string
  default     = "tg-arandu-frontend"
}

variable "tg_backend_name" {
  description = "Nome do Target Group para o Backend"
  type        = string
  default     = "tg-arandu-backend"
}

# Storage (EFS e S3)
variable "efs_name" {
  description = "Nome da tag do sistema de arquivos EFS"
  type        = string
  default     = "efs-arandu"
}

variable "s3_member_tag" {
  description = "Identificador unico por membro do grupo para evitar conflitos de nomes globais no S3"
  type        = string
  default     = "pedro"
}

# IMPORTANTE: CASO A GENTE DECIDA USAR NOMES FIXOS NOS BUCKETS, ALTERAR ABAIXO:

variable "bucket_bronze_name" {
  description = "Nome customizado para o bucket bronze (se omitido, sera gerado com s3_member_tag e account_id)"
  type        = string
  default     = null
}

variable "bucket_silver_name" {
  description = "Nome customizado para o bucket silver (se omitido, sera gerado com s3_member_tag e account_id)"
  type        = string
  default     = null
}

variable "bucket_gold_name" {
  description = "Nome customizado para o bucket gold (se omitido, sera gerado com s3_member_tag e account_id)"
  type        = string
  default     = null
}

# Banco de Dados (RDS MySQL)
variable "rds_instance_id" {
  description = "Identificador da instancia RDS"
  type        = string
  default     = "rds-arandu-db"
}

variable "rds_db_name" {
  description = "Nome do banco de dados inicial a ser criado no MySQL"
  type        = string
  default     = "bdClubeDesbravadores"
}

variable "rds_username" {
  description = "Usuario mestre do banco de dados"
  type        = string
  default     = "admin"
}

variable "rds_password" {
  description = "Senha mestre do RDS. Se omitida, uma senha forte sera gerada automaticamente"
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
  description = "Tamanho do disco em GB para o banco de dados"
  type        = number
  default     = 20
}

variable "sql_url" {
  description = "URL do script SQL inicial para popular o schema e dados"
  type        = string
  default     = "https://raw.githubusercontent.com/CCO-A-2-Grupo-02-Projeto-de-Extensao/projeto-extensao-backend/main/bdClubeDesbravadores.sql"
}

# Segredos e IAM
variable "jwt_secret" {
  description = "Chave secreta para assinatura dos tokens JWT. Se omitida, gerada automaticamente"
  type        = string
  default     = null
  sensitive   = true
}

variable "use_lab_instance_profile" {
  description = "Se verdadeiro, reaproveita o LabInstanceProfile pre-existente da AWS Academy em vez de tentar criar roles IAM"
  type        = bool
  default     = true
}
