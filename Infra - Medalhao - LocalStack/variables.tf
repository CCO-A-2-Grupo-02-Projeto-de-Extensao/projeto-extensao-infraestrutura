variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "bucket_bronze_name" {
  type    = string
  default = "arandu-bronze"
}

variable "bucket_silver_name" {
  type    = string
  default = "arandu-silver"
}

variable "bucket_gold_name" {
  type    = string
  default = "arandu-gold"
}

variable "bucket_documentos_name" {
  type    = string
  default = "arandu-documentos"
}
