# EFS: Sistema de arquivos compartilhado entre as instancias de Frontend

resource "aws_efs_file_system" "arandu" {
  creation_token   = "efs-arandu"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = var.efs_name
  }
}

# Mount Target na Subnet Publica 1 (us-east-1a)
resource "aws_efs_mount_target" "frontend_1" {
  file_system_id  = aws_efs_file_system.arandu.id
  subnet_id       = aws_subnet.subnets["frontend_1"].id
  security_groups = [aws_security_group.efs.id]
}

# Mount Target na Subnet Publica 2 (us-east-1b)
resource "aws_efs_mount_target" "frontend_2" {
  file_system_id  = aws_efs_file_system.arandu.id
  subnet_id       = aws_subnet.subnets["frontend_2"].id
  security_groups = [aws_security_group.efs.id]
}
