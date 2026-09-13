# S3: Armazenamento de Documentos da Aplicacao e Arquitetura Medalhao (Bronze, Silver, Gold)
#
# Os buckets sao criados via AWS CLI, e nao com o recurso aws_s3_bucket, porque a
# Service Control Policy do AWS Academy nega s3:GetBucketObjectLockConfiguration.
# O provider chama essa API toda vez que le um aws_s3_bucket, entao qualquer plan
# ou apply falharia com AccessDenied mesmo tendo criado o bucket com sucesso.

locals {
  bucket_documentos_name = "arandu-documentos-${data.aws_caller_identity.current.account_id}"
  bucket_bronze_name     = var.bucket_bronze_name != null ? var.bucket_bronze_name : "arandu-bronze-${var.s3_member_tag}-${data.aws_caller_identity.current.account_id}"
  bucket_silver_name     = var.bucket_silver_name != null ? var.bucket_silver_name : "arandu-silver-${var.s3_member_tag}-${data.aws_caller_identity.current.account_id}"
  bucket_gold_name       = var.bucket_gold_name != null ? var.bucket_gold_name : "arandu-gold-${var.s3_member_tag}-${data.aws_caller_identity.current.account_id}"
  bucket_documentos_arn  = "arn:aws:s3:::${local.bucket_documentos_name}"

  buckets = {
    documentos = local.bucket_documentos_name
    bronze     = local.bucket_bronze_name
    silver     = local.bucket_silver_name
    gold       = local.bucket_gold_name
  }
}

resource "terraform_data" "buckets" {
  for_each = local.buckets

  input = each.value

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      aws s3api head-bucket --bucket "${each.value}" 2>/dev/null \
        || aws s3api create-bucket --bucket "${each.value}" --region ${var.aws_region}
      aws s3api put-public-access-block \
        --bucket "${each.value}" \
        --public-access-block-configuration \
          BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
      aws s3api put-bucket-tagging \
        --bucket "${each.value}" \
        --tagging 'TagSet=[{Key=Name,Value=arandu-${each.key}},{Key=Projeto,Value=Arandu},{Key=GerenciadoPor,Value=Terraform}]'
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = <<-EOT
      aws s3 rm "s3://${self.input}" --recursive
      aws s3api delete-bucket --bucket "${self.input}"
    EOT
  }
}
