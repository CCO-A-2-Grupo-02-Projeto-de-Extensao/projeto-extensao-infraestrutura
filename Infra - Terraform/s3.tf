# S3: Armazenamento de Documentos da Aplicacao e Arquitetura Medalhao (Bronze, Silver, Gold)

locals {
  bucket_bronze_name = var.bucket_bronze_name != null ? var.bucket_bronze_name : "arandu-bronze-${var.s3_member_tag}-${data.aws_caller_identity.current.account_id}"
  bucket_silver_name = var.bucket_silver_name != null ? var.bucket_silver_name : "arandu-silver-${var.s3_member_tag}-${data.aws_caller_identity.current.account_id}"
  bucket_gold_name   = var.bucket_gold_name != null ? var.bucket_gold_name : "arandu-gold-${var.s3_member_tag}-${data.aws_caller_identity.current.account_id}"
}

# Bucket exclusivo por conta AWS - Documentos
resource "aws_s3_bucket" "documentos" {
  bucket        = "arandu-documentos-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "arandu-documentos"
  }
}

# Bloqueio total de acesso publico direto ao bucket de documentos
resource "aws_s3_bucket_public_access_block" "documentos" {
  bucket = aws_s3_bucket.documentos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Buckets da Arquitetura Medalhao

# Bucket Bronze
resource "aws_s3_bucket" "bronze" {
  bucket        = local.bucket_bronze_name
  force_destroy = true

  tags = {
    Name  = "arandu-bronze"
    Layer = "bronze"
  }
}

resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket Silver
resource "aws_s3_bucket" "silver" {
  bucket        = local.bucket_silver_name
  force_destroy = true

  tags = {
    Name  = "arandu-silver"
    Layer = "silver"
  }
}

resource "aws_s3_bucket_public_access_block" "silver" {
  bucket = aws_s3_bucket.silver.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket Gold
resource "aws_s3_bucket" "gold" {
  bucket        = local.bucket_gold_name
  force_destroy = true

  tags = {
    Name  = "arandu-gold"
    Layer = "gold"
  }
}

resource "aws_s3_bucket_public_access_block" "gold" {
  bucket = aws_s3_bucket.gold.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
