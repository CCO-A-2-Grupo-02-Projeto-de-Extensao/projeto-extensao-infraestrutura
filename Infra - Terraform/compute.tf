data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  user_data_frontend = <<-EOF
#!/bin/bash
until curl -4 --max-time 5 -s https://google.com > /dev/null 2>&1; do sleep 10; done
apt-get update -y
apt-get install -y docker.io nfs-common awscli

EFS_DNS="${aws_efs_file_system.arandu.id}.efs.${var.aws_region}.amazonaws.com"
mkdir -p /mnt/efs
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 "$EFS_DNS":/ /mnt/efs
echo "$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab

systemctl start docker
systemctl enable docker

mkdir -p /mnt/efs/frontend /opt/arandu
cat << 'DEPLOY' > /opt/arandu/deploy.sh
#!/bin/bash
set -e
aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_registry}
docker pull ${local.frontend_ecr_image}
docker run --rm -v /mnt/efs/frontend:/output ${local.frontend_ecr_image} sh -c "cp -r /usr/share/nginx/html/. /output/"
INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
docker rm -f frontend 2>/dev/null || true
docker run -d --name frontend --restart unless-stopped -p 80:80 -e INSTANCE_IP="$INSTANCE_IP" -v /mnt/efs/frontend:/usr/share/nginx/html:ro ${local.frontend_ecr_image}
DEPLOY
chmod 700 /opt/arandu/deploy.sh

mkdir -p /home/ubuntu/.ssh
cat << 'SSHKEY' > /home/ubuntu/.ssh/arandu-key.pem
${tls_private_key.ssh.private_key_pem}
SSHKEY
chmod 400 /home/ubuntu/.ssh/arandu-key.pem
chown ubuntu:ubuntu /home/ubuntu/.ssh/arandu-key.pem

/opt/arandu/deploy.sh
  EOF

  user_data_backend = <<-EOF
#!/bin/bash
until curl -4 --max-time 5 -s https://google.com > /dev/null 2>&1; do sleep 10; done
apt-get update -y
apt-get install -y mysql-client curl docker.io awscli

until mysql -h "${aws_db_instance.arandu.address}" -u "${var.rds_username}" -p"${local.rds_password}" -e "SELECT 1;" > /dev/null 2>&1; do sleep 15; done

curl -4 -s "${var.sql_url}" -o /tmp/bdClubeDesbravadores.sql
mysql -h "${aws_db_instance.arandu.address}" -u "${var.rds_username}" -p"${local.rds_password}" "${var.rds_db_name}" < /tmp/bdClubeDesbravadores.sql
rm -f /tmp/bdClubeDesbravadores.sql

systemctl start docker
systemctl enable docker

mkdir -p /opt/arandu
cat << 'DEPLOY' > /opt/arandu/deploy.sh
#!/bin/bash
set -e
aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_registry}
docker pull ${local.backend_ecr_image}
docker network create arandu-network 2>/dev/null || true
if ! docker inspect rabbitmq > /dev/null 2>&1; then
  docker run -d \
    --name rabbitmq \
    --network arandu-network \
    --restart unless-stopped \
    -p 127.0.0.1:5672:5672 \
    -p 127.0.0.1:15672:15672 \
    -e RABBITMQ_DEFAULT_USER=admin \
    -e RABBITMQ_DEFAULT_PASS=admin \
    rabbitmq:4-management
fi
for i in $(seq 1 30); do
  docker exec rabbitmq rabbitmq-diagnostics -q ping >/dev/null 2>&1 && break
  sleep 2
done
docker rm -f backend 2>/dev/null || true
docker run -d \
  --name backend \
  --network arandu-network \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_DATASOURCE_URL="jdbc:mysql://${aws_db_instance.arandu.address}:3306/${var.rds_db_name}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC" \
  -e SPRING_DATASOURCE_USERNAME="${var.rds_username}" \
  -e SPRING_DATASOURCE_PASSWORD="${local.rds_password}" \
  -e JWT_SECRET="${local.jwt_secret}" \
  -e APP_STORAGE_TYPE="s3" \
  -e APP_STORAGE_S3_BUCKET="${local.bucket_documentos_name}" \
  -e APP_STORAGE_S3_REGION="${var.aws_region}" \
  -e SPRING_RABBITMQ_HOST="rabbitmq" \
  -e SPRING_RABBITMQ_PORT="5672" \
  -e SPRING_RABBITMQ_USERNAME="admin" \
  -e SPRING_RABBITMQ_PASSWORD="admin" \
  "${local.backend_ecr_image}"
DEPLOY
chmod 700 /opt/arandu/deploy.sh
/opt/arandu/deploy.sh

  EOF
}

resource "aws_instance" "frontend_1" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.arandu.key_name
  subnet_id                   = aws_subnet.subnets["frontend_1"].id
  private_ip                  = "10.0.1.10"
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  associate_public_ip_address = true
  iam_instance_profile        = local.instance_profile_name
  user_data                   = local.user_data_frontend

  tags = {
    Name = "ec2-arandu-frontend-1"
    Role = "frontend"
  }

  depends_on = [
    aws_efs_mount_target.frontend_1,
    aws_efs_mount_target.frontend_2,
    terraform_data.ecr_sync
  ]
}

resource "aws_instance" "frontend_2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.arandu.key_name
  subnet_id                   = aws_subnet.subnets["frontend_2"].id
  private_ip                  = "10.0.4.10"
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  associate_public_ip_address = true
  iam_instance_profile        = local.instance_profile_name
  user_data                   = local.user_data_frontend

  tags = {
    Name = "ec2-arandu-frontend-2"
    Role = "frontend"
  }

  depends_on = [
    aws_efs_mount_target.frontend_1,
    aws_efs_mount_target.frontend_2,
    terraform_data.ecr_sync
  ]
}

resource "aws_instance" "backend" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.arandu.key_name
  subnet_id            = aws_subnet.subnets["backend"].id
  private_ip           = "10.0.2.10"
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile = local.instance_profile_name
  user_data            = local.user_data_backend

  tags = {
    Name = "ec2-arandu-backend"
    Role = "backend"
  }

  depends_on = [
    aws_nat_gateway.nat,
    aws_db_instance.arandu,
    terraform_data.ecr_sync
  ]
}
