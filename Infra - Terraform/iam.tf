# IAM: Permissoes para a instancia EC2 de Backend acessar o S3

# Role EC2 para o backend (criada apenas se nao estivermos usando LabInstanceProfile da AWS Academy)
resource "aws_iam_role" "backend" {
  count = var.use_lab_instance_profile ? 0 : 1
  name  = "arandu-backend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Politica de permissao para manipulacao de documentos no bucket S3
resource "aws_iam_role_policy" "backend_s3" {
  count = var.use_lab_instance_profile ? 0 : 1
  name  = "arandu-s3-policy"
  role  = aws_iam_role.backend[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documentos.arn,
          "${aws_s3_bucket.documentos.arn}/*"
        ]
      }
    ]
  })
}

# Instance Profile associado a role
resource "aws_iam_instance_profile" "backend" {
  count = var.use_lab_instance_profile ? 0 : 1
  name  = "arandu-backend-profile"
  role  = aws_iam_role.backend[0].name
}

locals {
  # Permite alternar perfeitamente entre conta pessoal e ambiente restrito Academy
  backend_iam_profile_name = var.use_lab_instance_profile ? "LabInstanceProfile" : aws_iam_instance_profile.backend[0].name
}
