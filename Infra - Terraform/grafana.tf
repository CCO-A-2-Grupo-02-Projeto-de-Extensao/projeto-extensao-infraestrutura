# Grafana de analise de dados: roda na EC2 de backend e sai pelo ALB em /grafana.
# As imagens sao buildadas do repo de documentacao (ecr.tf), que precisa continuar publico.

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "random_password" "grafana_leitura" {
  length  = 32
  special = false
}

locals {
  grafana_admin_password = var.grafana_admin_password != null ? var.grafana_admin_password : random_password.grafana_admin.result
  grafana_db_password    = random_password.grafana_leitura.result
  grafana_ecr_image      = "${aws_ecr_repository.arandu.repository_url}:grafana"
  grafana_dados_image    = "${aws_ecr_repository.arandu.repository_url}:grafana-dados"
}

resource "aws_lb_target_group" "grafana" {
  name        = var.tg_grafana_name
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled  = true
    path     = "/grafana/api/health"
    protocol = "HTTP"
    matcher  = "200-399"
  }

  tags = {
    Name = var.tg_grafana_name
  }
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.backend.id
  port             = 3000
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 230

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana*"]
    }
  }
}
