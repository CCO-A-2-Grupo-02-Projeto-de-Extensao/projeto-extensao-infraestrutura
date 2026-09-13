resource "aws_security_group" "alb" {
  name        = "arandu-sg-alb"
  description = "SG Load Balancer Arandu"
  vpc_id      = aws_vpc.main.id

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

resource "aws_security_group" "frontend" {
  name        = "arandu-sg-frontend"
  description = "SG Frontend Arandu"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Acesso SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_security_group" "efs" {
  name        = "arandu-sg-efs"
  description = "SG EFS Arandu"
  vpc_id      = aws_vpc.main.id

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

resource "aws_security_group" "backend" {
  name        = "arandu-sg-backend"
  description = "SG Backend Arandu"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "API vinda dos frontends"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "API vinda diretamente do ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

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

resource "aws_security_group" "db" {
  name        = "arandu-sg-db"
  description = "SG Database Arandu"
  vpc_id      = aws_vpc.main.id

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
