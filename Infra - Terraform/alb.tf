# Balanceador de Carga: Application Load Balancer, Target Groups e Rotas

# Application Load Balancer publico
resource "aws_lb" "frontend" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets = [
    aws_subnet.subnets["frontend_1"].id,
    aws_subnet.subnets["frontend_2"].id
  ]

  tags = {
    Name = var.alb_name
  }
}

# Target Group Frontend (Porta 80)
resource "aws_lb_target_group" "frontend" {
  name        = var.tg_frontend_name
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled  = true
    path     = "/"
    protocol = "HTTP"
    matcher  = "200-399"
  }

  tags = {
    Name = var.tg_frontend_name
  }
}

# Registro das duas instancias EC2 de Frontend no Target Group
resource "aws_lb_target_group_attachment" "frontend_1" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.frontend_1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "frontend_2" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.frontend_2.id
  port             = 80
}

# Target Group Backend (Porta 8080)

resource "aws_lb_target_group" "backend" {
  name        = var.tg_backend_name
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/v3/api-docs"
    protocol            = "HTTP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
    matcher             = "200-399"
  }

  tags = {
    Name = var.tg_backend_name
  }
}

# Registro da instancia de backend no Target Group

resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = aws_instance.backend.id
  port             = 8080
}

# Listener HTTP (Porta 80) e Regras de Roteamento
# Listener padrao: direciona todo trafego default para os Frontends

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# Regras especificas de path para rotear APIs e Swagger direto ao Backend

locals {
  backend_routes = {
    "swagger_ui"     = { priority = 10,  path = "/swagger-ui*" }
    "api_docs"       = { priority = 20,  path = "/v3/api-docs*" }
    "auth"           = { priority = 30,  path = "/auth*" }
    "usuarios"       = { priority = 40,  path = "/usuarios*" }
    "documentos"     = { priority = 50,  path = "/documentos*" }
    "comorbidades"   = { priority = 60,  path = "/comorbidades*" }
    "diagnosticos"   = { priority = 70,  path = "/diagnosticos*" }
    "fichas_medicas" = { priority = 80,  path = "/fichas-medicas*" }
    "medicacoes"     = { priority = 90,  path = "/medicacoes*" }
    "medicamentos"   = { priority = 100, path = "/medicamentos*" }
    "pessoas"        = { priority = 110, path = "/pessoas*" }
    "ocorrencias"    = { priority = 120, path = "/ocorrencias*" }
    "unidades"       = { priority = 130, path = "/unidades*" }
    "generos"        = { priority = 140, path = "/generos*" }
    "classes"        = { priority = 150, path = "/classes*" }
    "cargos"         = { priority = 160, path = "/cargos*" }
    "especialidades" = { priority = 170, path = "/especialidades*" }
    "turmas"         = { priority = 180, path = "/turmas*" }
    "chamadas"       = { priority = 190, path = "/chamadas*" }
    "eventos"        = { priority = 200, path = "/eventos*" }
    "presencas"      = { priority = 210, path = "/presencas*" }
  }
}

resource "aws_lb_listener_rule" "backend_routes" {
  for_each = local.backend_routes

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}
