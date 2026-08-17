# Observabilidade: Dashboard do CloudWatch (Metricas de EC2, ALB e RDS)

resource "aws_cloudwatch_dashboard" "arandu" {
  dashboard_name = "Arandu-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Cabecalho 
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Arandu Digital — Monitoramento de Infraestrutura\nDashboard gerado via Terraform | Regiao: **${var.aws_region}**"
        }
      },
      # CPU EC2
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "CPU das Instancias EC2 (%)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.frontend_1.id, { label = "Frontend 1", color = "#1f77b4" }],
            [".", ".", ".", aws_instance.frontend_2.id, { label = "Frontend 2", color = "#ff7f0e" }],
            [".", ".", ".", aws_instance.backend.id, { label = "Backend", color = "#2ca02c" }]
          ]
          annotations = {
            horizontal = [
              { label = "Alerta 80%", value = 80, color = "#d62728", fill = "above" }
            ]
          }
          yAxis = {
            left = { min = 0, max = 100, label = "%" }
          }
        }
      },
      # Requisicoes e Saude ALB 
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "Requisicoes e Hosts Saudaveis (ALB)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.frontend.arn_suffix, { stat = "Sum", label = "Requisicoes (sum)", color = "#1f77b4" }],
            [".", "HealthyHostCount", ".", aws_lb.frontend.arn_suffix, { stat = "Average", label = "Hosts saudaveis", color = "#2ca02c", yAxis = "right" }]
          ]
          yAxis = {
            left  = { label = "Requisicoes", min = 0 }
            right = { label = "Hosts", min = 0 }
          }
        }
      },
      # Erros 5xx ALB 
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Erros 5xx (ALB)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.frontend.arn_suffix, { stat = "Sum", label = "5xx Target", color = "#d62728" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", aws_lb.frontend.arn_suffix, { stat = "Sum", label = "5xx ELB", color = "#ff7f0e" }]
          ]
          annotations = {
            horizontal = [
              { label = "Limite", value = 10, color = "#d62728" }
            ]
          }
          yAxis = {
            left = { min = 0 }
          }
        }
      },
      # Erros 4xx ALB 
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Erros 4xx (ALB)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.frontend.arn_suffix, { stat = "Sum", label = "4xx Target", color = "#ff7f0e" }],
            [".", "HTTPCode_ELB_4XX_Count", ".", aws_lb.frontend.arn_suffix, { stat = "Sum", label = "4xx ELB", color = "#ffbb78" }]
          ]
          yAxis = {
            left = { min = 0 }
          }
        }
      },
      # Latencia ALB 
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title   = "Latencia de Resposta (ALB)"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.frontend.arn_suffix, { stat = "p50", label = "p50", color = "#2ca02c" }],
            [".", ".", ".", aws_lb.frontend.arn_suffix, { stat = "p90", label = "p90", color = "#ff7f0e" }],
            [".", ".", ".", aws_lb.frontend.arn_suffix, { stat = "p99", label = "p99", color = "#d62728" }]
          ]
          annotations = {
            horizontal = [
              { label = "SLA 1s", value = 1, color = "#d62728" }
            ]
          }
          yAxis = {
            left = { min = 0, label = "segundos" }
          }
        }
      },
      # RDS CPU e Conexoes 
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "RDS — CPU e Conexoes"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.arandu.identifier, { label = "CPU (%)", color = "#1f77b4", yAxis = "left" }],
            [".", "DatabaseConnections", ".", aws_db_instance.arandu.identifier, { label = "Conexoes", color = "#ff7f0e", yAxis = "right" }]
          ]
          yAxis = {
            left  = { label = "CPU (%)", min = 0, max = 100 }
            right = { label = "Conexoes", min = 0 }
          }
        }
      },
      # RDS Armazenamento e Memoria 
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "RDS — Storage e Memoria Livre"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.arandu.identifier, { stat = "Minimum", label = "Storage Livre", color = "#2ca02c" }],
            [".", "FreeableMemory", ".", aws_db_instance.arandu.identifier, { stat = "Minimum", label = "Memoria Livre", color = "#17becf" }]
          ]
          yAxis = {
            left = { min = 0, label = "bytes" }
          }
        }
      },
      # RDS Latencia 
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "RDS — Latencia de Leitura e Escrita"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", aws_db_instance.arandu.identifier, { stat = "Average", label = "Leitura", color = "#1f77b4" }],
            [".", "WriteLatency", ".", aws_db_instance.arandu.identifier, { stat = "Average", label = "Escrita", color = "#ff7f0e" }]
          ]
          yAxis = {
            left = { min = 0, label = "segundos" }
          }
        }
      }
    ]
  })
}
