resource "aws_efs_file_system" "arandu" {
  creation_token   = "efs-arandu"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = var.efs_name
  }
}

resource "aws_efs_mount_target" "frontend_1" {
  file_system_id  = aws_efs_file_system.arandu.id
  subnet_id       = aws_subnet.subnets["frontend_1"].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "frontend_2" {
  file_system_id  = aws_efs_file_system.arandu.id
  subnet_id       = aws_subnet.subnets["frontend_2"].id
  security_groups = [aws_security_group.efs.id]
}
