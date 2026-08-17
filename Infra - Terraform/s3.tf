# S3: Armazenamento de Documentos da Aplicacao

# Bucket exclusivo por conta AWS
resource "aws_s3_bucket" "documentos" {
  bucket        = "arandu-documentos-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "arandu-documentos"
  }
}

# Bloqueio total de acesso publico direto ao bucket
resource "aws_s3_bucket_public_access_block" "documentos" {
  bucket = aws_s3_bucket.documentos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
