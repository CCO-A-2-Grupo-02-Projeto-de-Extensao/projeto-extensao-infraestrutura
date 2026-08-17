# Security Groups da Infraestrutura

# 1. Security Group do Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "arandu-sg-alb"
  description = "SG Load Balancer Arandu"
  vpc_id      = aws_vpc.main.id

  # HTTP publico vindo da internet
  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Trafego de saida liberado"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "arandu-sg-alb"
  }
}

# 2. Security Group das Instancias de Frontend (Nginx)
resource "aws_security_group" "frontend" {
  name        = "arandu-sg-frontend"
  description = "SG Frontend Arandu"
  vpc_id      = aws_vpc.main.id

  # SSH aberto para administracao
  ingress {
    description = "Acesso SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP apenas vindo do Load Balancer
  ingress {
    description     = "HTTP vindo do ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Trafego de saida liberado"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "arandu-sg-frontend"
  }
}

# 3. Security Group do EFS (Storage compartilhado)
resource "aws_security_group" "efs" {
  name        = "arandu-sg-efs"
  description = "SG EFS Arandu"
  vpc_id      = aws_vpc.main.id

  # NFS (porta 2049) aceito apenas dos frontends
  ingress {
    description     = "NFS vindo dos frontends"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    description = "Trafego de saida liberado"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "arandu-sg-efs"
  }
}

# 4. Security Group da Instancia de Backend (Spring Boot na rede privada)
resource "aws_security_group" "backend" {
  name        = "arandu-sg-backend"
  description = "SG Backend Arandu"
  vpc_id      = aws_vpc.main.id

  # API 8080 aceita do Frontend
  ingress {
    description     = "API vinda dos frontends"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  # API 8080 aceita direto do ALB (para rotas de Swagger/API expostas no LB)
  ingress {
    description     = "API vinda diretamente do ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH apenas a partir do Frontend (usando frontend como bastion/jump host)
  ingress {
    description     = "SSH interno vindo do frontend"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    description = "Trafego de saida liberado"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "arandu-sg-backend"
  }
}

# 5. Security Group do RDS (MySQL na rede privada)
resource "aws_security_group" "db" {
  name        = "arandu-sg-db"
  description = "SG Database Arandu"
  vpc_id      = aws_vpc.main.id

  # Conexao MySQL liberada exclusivamente para o Backend
  ingress {
    description     = "MySQL vindo do backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  ingress {
    description     = "SSH vindo do backend"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    description = "Trafego de saida liberado"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "arandu-sg-db"
  }
}
