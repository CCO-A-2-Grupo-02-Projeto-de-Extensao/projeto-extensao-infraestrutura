data "aws_iam_role" "lambda_execution" {
  name = var.lambda_execution_role_name
}

locals {
  factors_ingestion_functions = {
    inmet = {
      handler  = "ingestion.inmet_handler"
      schedule = "cron(0 6 1 * ? *)"
    }
    musicbrainz = {
      handler  = "ingestion.musicbrainz_handler"
      schedule = "cron(0 7 ? * MON *)"
    }
    anbima = {
      handler  = "ingestion.anbima_handler"
      schedule = "cron(0 8 1 * ? *)"
    }
  }

  bronze_arn               = "arn:aws:s3:::${local.bucket_bronze_name}"
  silver_arn               = "arn:aws:s3:::${local.bucket_silver_name}"
  manifest_lock_table_name = "arandu-fatores-manifest-lock-${data.aws_caller_identity.current.account_id}"
}

resource "terraform_data" "lambda_layer_build" {
  input = filesha256("${path.module}/lambda-requirements.txt")

  provisioner "local-exec" {
    command = "\"${var.lambda_build_python}\" \"${path.module}/build_lambda_layer.py\" \"${path.module}/build/layer/python\" \"${path.module}/lambda-requirements.txt\""
  }
}

data "archive_file" "lambda_code" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src"
  output_path = "${path.module}/build/lambda.zip"
  depends_on  = [terraform_data.lambda_layer_build]
}

data "archive_file" "lambda_layer" {
  type        = "zip"
  source_dir  = "${path.module}/build/layer"
  output_path = "${path.module}/build/lambda-layer.zip"
  depends_on  = [terraform_data.lambda_layer_build]
}

resource "aws_lambda_layer_version" "xlrd" {
  layer_name          = "arandu-fatores-xlrd"
  description         = "Leitor de planilhas XLS para a ingestao ANBIMA"
  filename            = data.archive_file.lambda_layer.output_path
  source_code_hash    = data.archive_file.lambda_layer.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

resource "aws_dynamodb_table" "manifest_lock" {
  name         = local.manifest_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "lock_id"

  attribute {
    name = "lock_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

resource "aws_iam_role_policy" "factors_lambdas" {
  # No AWS Academy a conta nega iam:PutRolePolicy e a LabRole ja tem esses
  # acessos pelas VocLabPolicy, entao a politica so e criada sob demanda.
  count = var.manage_lambda_role_policy ? 1 : 0

  name = "arandu-fatores-lambda-access"
  role = data.aws_iam_role.lambda_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadBronze"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetObject"]
        Resource = [
          local.bronze_arn,
          "${local.bronze_arn}/*"
        ]
      },
      {
        Sid      = "WriteBronzeAndSilver"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = ["${local.bronze_arn}/*", "${local.silver_arn}/*"]
      },
      {
        Sid      = "ManifestLock"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = [aws_dynamodb_table.manifest_lock.arn]
      },
      {
        Sid      = "CreateLambdaLogGroups"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = "*"
      },
      {
        Sid    = "WriteLambdaLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/arandu-fatores-*:*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "ingestion" {
  for_each = local.factors_ingestion_functions

  function_name    = "arandu-fatores-${each.key}"
  description      = "Ingestao Bronze da fonte ${each.key}"
  role             = data.aws_iam_role.lambda_execution.arn
  runtime          = "python3.12"
  handler          = each.value.handler
  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256
  timeout          = 900
  memory_size      = 1024
  layers           = [aws_lambda_layer_version.xlrd.arn]

  ephemeral_storage {
    size = 10240
  }

  environment {
    variables = {
      BRONZE_BUCKET       = local.bucket_bronze_name
      MANIFEST_LOCK_TABLE = aws_dynamodb_table.manifest_lock.name
      INMET_START_YEAR    = tostring(var.inmet_start_year)
    }
  }

  depends_on = [aws_iam_role_policy.factors_lambdas]
}

resource "aws_lambda_function" "silver" {
  function_name                  = "arandu-fatores-silver"
  description                    = "Transforma objetos Bronze em tabelas Silver"
  role                           = data.aws_iam_role.lambda_execution.arn
  runtime                        = "python3.12"
  handler                        = "silver.handler"
  filename                       = data.archive_file.lambda_code.output_path
  source_code_hash               = data.archive_file.lambda_code.output_base64sha256
  timeout                        = 900
  memory_size                    = 10240
  reserved_concurrent_executions = 1
  layers                         = [aws_lambda_layer_version.xlrd.arn]

  ephemeral_storage {
    size = 10240
  }

  environment {
    variables = {
      BRONZE_BUCKET = local.bucket_bronze_name
      SILVER_BUCKET = local.bucket_silver_name
    }
  }

  depends_on = [aws_iam_role_policy.factors_lambdas]
}

resource "aws_cloudwatch_log_group" "factors_lambda" {
  for_each = merge(
    { for name, function in aws_lambda_function.ingestion : name => function },
    { silver = aws_lambda_function.silver }
  )

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_event_rule" "ingestion" {
  for_each = local.factors_ingestion_functions

  name                = "arandu-fatores-${each.key}-schedule"
  description         = "Agenda de ingestao para ${each.key}"
  schedule_expression = each.value.schedule
}

resource "aws_cloudwatch_event_target" "ingestion" {
  for_each = local.factors_ingestion_functions

  rule      = aws_cloudwatch_event_rule.ingestion[each.key].name
  target_id = "${each.key}-lambda"
  arn       = aws_lambda_function.ingestion[each.key].arn
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = local.factors_ingestion_functions

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingestion[each.key].arn
}

resource "aws_lambda_permission" "bronze_s3" {
  statement_id   = "AllowBronzeBucketInvokeSilver"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.silver.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = local.bronze_arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "bronze" {
  bucket = local.bucket_bronze_name

  dynamic "lambda_function" {
    for_each = toset(["clima/", "eventos/", "feriados/"])
    content {
      lambda_function_arn = aws_lambda_function.silver.arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = lambda_function.value
    }
  }

  depends_on = [
    terraform_data.buckets["bronze"],
    aws_lambda_permission.bronze_s3
  ]
}

output "fatores_lambda_ingestion" {
  description = "Lambdas de ingestao Bronze"
  value       = { for source, function in aws_lambda_function.ingestion : source => function.function_name }
}

output "fatores_lambda_silver" {
  description = "Lambda que processa os eventos S3 da Bronze"
  value       = aws_lambda_function.silver.function_name
}
