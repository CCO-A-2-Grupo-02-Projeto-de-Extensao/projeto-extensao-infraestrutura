output "localstack_endpoint" {
  value = var.localstack_endpoint
}

output "bucket_bronze" {
  value = aws_s3_bucket.bronze.bucket
}

output "bucket_silver" {
  value = aws_s3_bucket.silver.bucket
}

output "bucket_gold" {
  value = aws_s3_bucket.gold.bucket
}

output "bucket_documentos" {
  value = aws_s3_bucket.documentos.bucket
}
