# Rede: VPC, Subnets, Gateways, Tabelas de Rota e NACL

# VPC principal
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.vpc_name
  }
}

# Subnets publicas e privadas definidas no mapa
resource "aws_subnet" "subnets" {
  for_each = var.subnets_config

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.map_public_ip_on_launch

  tags = {
    Name = each.value.name
  }
}

# Internet Gateway e Roteamento Publico

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "internet-gateway-arandu"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "rota-publica-arandu"
  }
}

# Associa as subnets de frontend a tabela publica
resource "aws_route_table_association" "public" {
  for_each = toset(["frontend_1", "frontend_2"])

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway e Roteamento Privado

# IP elastico dedicado para saida de internet da rede privada
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "eip-nat-arandu"
  }
}

# NAT Gateway colocado na subnet publica 1
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.subnets["frontend_1"].id

  tags = {
    Name = "nat-arandu"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "rota-privada-arandu"
  }
}

# Associa backend e bancos a tabela de rotas privadas (com saida pelo NAT)
resource "aws_route_table_association" "private" {
  for_each = toset(["backend", "db_1", "db_2"])

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.private.id
}

# NACL (Network Access Control List) para as subnets publicas

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id

  subnet_ids = [
    aws_subnet.subnets["frontend_1"].id,
    aws_subnet.subnets["frontend_2"].id
  ]

  # Regras de Ingress (Entrada)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  ingress {
    rule_no    = 115
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 2049
    to_port    = 2049
  }

  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Regra de Egress (Saida - Todo trafego liberado)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "nacl-publica-arandu"
  }
}
