# Backup completo diário do banco de dados
#
# O script scripts/backup_banco.sh é instalado na EC2 de backend (a única que
# enxerga o RDS na subnet privada) e disparado por um Cron Job diário. Ele gera o
# dump SQL com a data ISO no nome, envia para o bucket S3 de backups e notifica o
# administrador por e-mail no sucesso e no erro.
#
# O script vai embutido no user data em gzip+base64: o user data é um heredoc
# interpolado pelo Terraform, e qualquer ${VAR} do shell seria lido como
# interpolação. Em base64 o conteúdo trafega intacto, e o gzip é necessário
# porque o user data da AWS tem limite de 16 KB — só o script em base64 puro
# consome 12,8 KB dos 16,3 KB que o user data do backend ocupa no total.

# O aviso sai por SNS: a AWS bloqueia a saida SMTP (25/465/587) nas instancias
# EC2 de contas sandbox, entao o envio direto por Gmail nao completa a conexao.
# A inscricao por e-mail exige um clique de confirmacao na mensagem que a AWS
# manda ao criar a subscription.
resource "aws_sns_topic" "backup" {
  name = "arandu-backup-banco"

  tags = {
    Name = "arandu-backup-banco"
  }
}

resource "aws_sns_topic_subscription" "backup_email" {
  topic_arn = aws_sns_topic.backup.arn
  protocol  = "email"
  endpoint  = local.backup_mail_to
}

locals {
  backup_script_gz = base64gzip(file("${path.module}/scripts/backup_banco.sh"))
  backup_mail_to   = var.backup_email_to != null ? var.backup_email_to : local.mail_username

  # Trecho acrescentado ao user data do backend (ver compute.tf).
  backup_install = <<-EOF
mkdir -p /etc/arandu /opt/arandu /var/backups/arandu
chmod 700 /var/backups/arandu

cat << 'BACKUPENV' > /etc/arandu/backup.env
DB_HOST='${aws_db_instance.arandu.address}'
DB_NAME='${var.rds_db_name}'
DB_USER='${var.rds_username}'
DB_PASSWORD='${local.rds_password}'
S3_BUCKET='${local.bucket_backups_name}'
S3_PREFIX='${var.backup_s3_prefix}'
AWS_REGION='${var.aws_region}'
BACKUP_DIR='/var/backups/arandu'
LOCAL_RETENTION_DAYS='${var.backup_local_retention_days}'
S3_RETENTION_DAYS='${var.backup_s3_retention_days}'
SNS_TOPIC_ARN='${aws_sns_topic.backup.arn}'
MAIL_TO='${local.backup_mail_to}'
MAIL_FROM='${local.mail_username}'
MAIL_SMTP='${var.backup_mail_smtp}'
MAIL_USERNAME='${local.mail_username}'
MAIL_PASSWORD='${local.mail_password}'
BACKUPENV
chmod 600 /etc/arandu/backup.env

echo '${local.backup_script_gz}' | base64 -d | gunzip -c > /opt/arandu/backup_banco.sh
chmod 700 /opt/arandu/backup_banco.sh

touch /var/log/arandu-backup.log
chmod 640 /var/log/arandu-backup.log

cat << 'BACKUPCRON' > /etc/cron.d/arandu-backup
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# Backup completo do banco Arandu (horario em UTC)
${var.backup_cron_schedule} root /opt/arandu/backup_banco.sh >> /var/log/arandu-backup.log 2>&1
BACKUPCRON
chmod 644 /etc/cron.d/arandu-backup

cat << 'BACKUPROTATE' > /etc/logrotate.d/arandu-backup
/var/log/arandu-backup.log {
  weekly
  rotate 8
  compress
  missingok
  notifempty
  copytruncate
}
BACKUPROTATE

systemctl enable cron
systemctl restart cron
  EOF
}
