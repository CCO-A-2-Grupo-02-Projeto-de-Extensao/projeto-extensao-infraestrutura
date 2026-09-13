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
          local.bucket_documentos_arn,
          "${local.bucket_documentos_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backend" {
  count = var.use_lab_instance_profile ? 0 : 1
  name  = "arandu-backend-profile"
  role  = aws_iam_role.backend[0].name
}

locals {
  backend_iam_profile_name = var.use_lab_instance_profile ? "LabInstanceProfile" : aws_iam_instance_profile.backend[0].name
}
