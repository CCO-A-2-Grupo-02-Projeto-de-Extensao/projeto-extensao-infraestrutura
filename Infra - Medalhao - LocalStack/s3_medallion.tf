resource "aws_s3_bucket" "bronze" {
  bucket        = var.bucket_bronze_name
  force_destroy = true

  tags = {
    Name  = var.bucket_bronze_name
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

resource "aws_s3_bucket" "silver" {
  bucket        = var.bucket_silver_name
  force_destroy = true

  tags = {
    Name  = var.bucket_silver_name
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

resource "aws_s3_bucket" "gold" {
  bucket        = var.bucket_gold_name
  force_destroy = true

  tags = {
    Name  = var.bucket_gold_name
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

resource "aws_s3_bucket" "documentos" {
  bucket        = var.bucket_documentos_name
  force_destroy = true

  tags = {
    Name = var.bucket_documentos_name
  }
}

resource "aws_s3_bucket_public_access_block" "documentos" {
  bucket = aws_s3_bucket.documentos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
