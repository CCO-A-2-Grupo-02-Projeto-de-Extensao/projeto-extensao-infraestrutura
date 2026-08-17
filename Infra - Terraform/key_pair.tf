# Chave SSH: Geracao automatica do par de chaves e registro na AWS

# Gera chave RSA de 4096 bits
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Registra a chave publica na AWS
resource "aws_key_pair" "arandu" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh.public_key_openssh

  tags = {
    Name = var.key_name
  }
}

# Salva a chave privada localmente no arquivo .pem com permissao restrita
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/arandu-key.pem"
  file_permission = "0400"
}
