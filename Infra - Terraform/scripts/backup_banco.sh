#!/usr/bin/env bash
# =============================================================================
# Arandu — Backup completo diário do banco de dados
#
# Executado pelo cron da EC2 de backend (/etc/cron.d/arandu-backup). O script:
#   1. gera um dump SQL completo do RDS MySQL, com a data ISO (aaaa-mm-dd) no nome;
#   2. envia o arquivo para o bucket S3 de backups;
#   3. avisa o administrador por e-mail, tanto no sucesso quanto no erro;
#      (via SNS, porque a AWS bloqueia saida SMTP em instancias EC2 de contas
#      sandbox; o SMTP direto fica como alternativa para outros ambientes)
#   4. aplica a retenção local e a retenção no S3.
#
# A configuração vem de /etc/arandu/backup.env, escrito pelo Terraform
# (backup.tf) no provisionamento da instância. Nenhum segredo fica neste arquivo.
#
# Execução manual (útil para o teste de restauração):
#   sudo /opt/arandu/backup_banco.sh
# =============================================================================
set -uo pipefail

CONFIG_FILE="${ARANDU_BACKUP_ENV:-/etc/arandu/backup.env}"
if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "[ERRO] Arquivo de configuração não encontrado: $CONFIG_FILE" >&2
    exit 1
fi

: "${DB_HOST:?DB_HOST não definido}"
: "${DB_NAME:?DB_NAME não definido}"
: "${DB_USER:?DB_USER não definido}"
: "${DB_PASSWORD:?DB_PASSWORD não definido}"
: "${S3_BUCKET:?S3_BUCKET não definido}"

S3_PREFIX="${S3_PREFIX:-backups/banco}"
AWS_REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/arandu}"
LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-3}"
S3_RETENTION_DAYS="${S3_RETENTION_DAYS:-30}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-}"
MAIL_TO="${MAIL_TO:-}"
MAIL_FROM="${MAIL_FROM:-$MAIL_TO}"
MAIL_SMTP="${MAIL_SMTP:-smtp://smtp.gmail.com:587}"
MAIL_USERNAME="${MAIL_USERNAME:-}"
MAIL_PASSWORD="${MAIL_PASSWORD:-}"

DATA_ISO="$(date +%F)"                       # aaaa-mm-dd, exigido no nome do arquivo
MOMENTO="$(date +'%d/%m/%Y %H:%M:%S %Z')"
HOSTNAME_LOCAL="$(hostname -f 2>/dev/null || hostname)"
ARQUIVO="${DB_NAME}-${DATA_ISO}.sql"
CAMINHO="${BACKUP_DIR}/${ARQUIVO}"
CHAVE_S3="${S3_PREFIX}/${DATA_ISO:0:4}/${DATA_ISO:5:2}/${ARQUIVO}"
DESTINO_S3="s3://${S3_BUCKET}/${CHAVE_S3}"
CRED_FILE=""

log()  { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"; }
erro() { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [ERRO] $*" >&2; }

limpar() {
    [[ -n "$CRED_FILE" && -f "$CRED_FILE" ]] && rm -f "$CRED_FILE"
}
trap limpar EXIT

# -----------------------------------------------------------------------------
# Notificação do administrador
#
# Via preferida: SNS, que fala HTTPS. A AWS bloqueia as portas SMTP (25, 465,
# 587, 2525) na saída das instâncias EC2 em contas sandbox, então o curl abaixo
# só funciona fora desse cenário — por isso ele é a segunda opção, e não a
# primeira.
# -----------------------------------------------------------------------------
notificar() {
    local assunto="$1" corpo="$2"

    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        if aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --region "$AWS_REGION" \
            --subject "$assunto" \
            --message "$corpo" > /dev/null 2>&1; then
            log "Aviso publicado no SNS (${SNS_TOPIC_ARN}): ${assunto}"
            return 0
        fi
        erro "Falha ao publicar o aviso no SNS — tentando SMTP."
    fi

    enviar_email "$assunto" "$corpo"
}

enviar_email() {
    local assunto="$1" corpo="$2" mensagem

    if [[ -z "$MAIL_TO" || -z "$MAIL_USERNAME" || -z "$MAIL_PASSWORD" ]]; then
        log "Notificação desativada (sem SNS_TOPIC_ARN e sem MAIL_TO/MAIL_USERNAME/MAIL_PASSWORD)."
        return 0
    fi

    mensagem="$(mktemp)"
    {
        echo "From: Arandu Backup <${MAIL_FROM}>"
        echo "To: ${MAIL_TO}"
        echo "Subject: ${assunto}"
        echo "Date: $(date -R)"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/plain; charset=\"UTF-8\""
        echo
        echo "$corpo"
    } > "$mensagem"

    if curl --silent --show-error --ssl-reqd --max-time 60 \
        --url "$MAIL_SMTP" \
        --user "${MAIL_USERNAME}:${MAIL_PASSWORD}" \
        --mail-from "$MAIL_FROM" \
        --mail-rcpt "$MAIL_TO" \
        --upload-file "$mensagem"; then
        log "E-mail enviado para ${MAIL_TO}: ${assunto}"
    else
        erro "Falha ao enviar o e-mail de notificação para ${MAIL_TO}."
    fi

    rm -f "$mensagem"
}

falhar() {
    local etapa="$1" detalhe="${2:-}"
    erro "$etapa"
    notificar "[Arandu] FALHA no backup do banco em ${DATA_ISO}" \
"O backup completo do banco de dados Arandu FALHOU.

Data/hora.....: ${MOMENTO}
Instância.....: ${HOSTNAME_LOCAL}
Banco.........: ${DB_NAME} em ${DB_HOST}
Arquivo.......: ${ARQUIVO}
Destino S3....: ${DESTINO_S3}

Etapa com erro: ${etapa}
${detalhe:+Detalhe: ${detalhe}}

Verifique o log em /var/log/arandu-backup.log na instância de backend.
-- 
Mensagem automática do cron de backup (Arandu Digital)."
    exit 1
}

# -----------------------------------------------------------------------------
# 1. Dump SQL completo
# -----------------------------------------------------------------------------
log "Iniciando backup completo de '${DB_NAME}' (${DB_HOST})."
mkdir -p "$BACKUP_DIR" || falhar "Criação do diretório local ${BACKUP_DIR}"
chmod 700 "$BACKUP_DIR"

# A senha vai por arquivo temporário: na linha de comando ela apareceria no 'ps'.
CRED_FILE="$(mktemp)"
chmod 600 "$CRED_FILE"
cat > "$CRED_FILE" <<CRED
[client]
host=${DB_HOST}
user=${DB_USER}
password=${DB_PASSWORD}
CRED

dump_erro="$(mktemp)"
if ! mysqldump --defaults-extra-file="$CRED_FILE" \
    --single-transaction \
    --routines --triggers \
    --set-gtid-purged=OFF \
    --no-tablespaces \
    --databases "$DB_NAME" > "$CAMINHO" 2> "$dump_erro"; then
    detalhe="$(tail -n 5 "$dump_erro")"
    rm -f "$dump_erro" "$CAMINHO"
    falhar "Geração do dump SQL (mysqldump)" "$detalhe"
fi
rm -f "$dump_erro"

if [[ ! -s "$CAMINHO" ]]; then
    falhar "Geração do dump SQL (mysqldump)" "O arquivo ${CAMINHO} ficou vazio."
fi

chmod 600 "$CAMINHO"
TAMANHO="$(du -h "$CAMINHO" | cut -f1)"
log "Dump gerado: ${CAMINHO} (${TAMANHO})."

# -----------------------------------------------------------------------------
# 2. Envio para o bucket S3
# -----------------------------------------------------------------------------
upload_erro="$(mktemp)"
if ! aws s3 cp "$CAMINHO" "$DESTINO_S3" --region "$AWS_REGION" --only-show-errors 2> "$upload_erro"; then
    detalhe="$(tail -n 5 "$upload_erro")"
    rm -f "$upload_erro"
    falhar "Envio do arquivo para o S3" "$detalhe"
fi
rm -f "$upload_erro"

# Confirma que o objeto chegou íntegro: um upload "silencioso" que não grava nada
# é exatamente o tipo de backup que só se descobre quebrado na hora de restaurar.
TAMANHO_LOCAL="$(stat -c %s "$CAMINHO")"
TAMANHO_S3="$(aws s3api head-object --bucket "$S3_BUCKET" \
    --key "$CHAVE_S3" --region "$AWS_REGION" \
    --query 'ContentLength' --output text 2>/dev/null || echo "")"

if [[ "$TAMANHO_S3" != "$TAMANHO_LOCAL" ]]; then
    falhar "Verificação do objeto no S3" \
        "Tamanho local ${TAMANHO_LOCAL} bytes, tamanho no S3 '${TAMANHO_S3:-ausente}'."
fi
log "Upload confirmado em ${DESTINO_S3} (${TAMANHO_LOCAL} bytes)."

# -----------------------------------------------------------------------------
# 3. Retenção local e no S3
# -----------------------------------------------------------------------------
if [[ "$LOCAL_RETENTION_DAYS" -gt 0 ]]; then
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB_NAME}-*.sql" \
        -mtime "+${LOCAL_RETENTION_DAYS}" -print -delete \
        | while read -r antigo; do log "Removido backup local expirado: ${antigo}"; done
fi

if [[ "$S3_RETENTION_DAYS" -gt 0 ]]; then
    limite="$(date -u -d "-${S3_RETENTION_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)"
    expirados="$(aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" --prefix "${S3_PREFIX}/" --region "$AWS_REGION" \
        --query "Contents[?LastModified<='${limite}'].Key" --output text 2>/dev/null || echo "")"

    if [[ -n "$expirados" && "$expirados" != "None" ]]; then
        for chave in $expirados; do
            # Trava de segurança: o backup recém-enviado nunca entra na limpeza,
            # por mais que o filtro de data ou o relógio da instância errem.
            if [[ "$chave" == "$CHAVE_S3" ]]; then
                erro "Retenção tentou remover o backup do dia (${chave}) — ignorado. Verifique S3_RETENTION_DAYS e o relógio da instância."
                continue
            fi
            if aws s3 rm "s3://${S3_BUCKET}/${chave}" --region "$AWS_REGION" --only-show-errors; then
                log "Removido backup expirado no S3: ${chave}"
            fi
        done
    fi
fi

# -----------------------------------------------------------------------------
# 4. E-mail de sucesso
# -----------------------------------------------------------------------------
notificar "[Arandu] Backup do banco concluido em ${DATA_ISO}" \
"O backup completo do banco de dados Arandu foi criado com sucesso.

Data/hora.....: ${MOMENTO}
Instância.....: ${HOSTNAME_LOCAL}
Banco.........: ${DB_NAME} em ${DB_HOST}
Arquivo.......: ${ARQUIVO} (${TAMANHO})
Destino S3....: ${DESTINO_S3}
Cópia local...: ${CAMINHO} (retida por ${LOCAL_RETENTION_DAYS} dia(s))
Retenção S3...: ${S3_RETENTION_DAYS} dia(s)

Restauração:
  aws s3 cp ${DESTINO_S3} ./${ARQUIVO}
  mysql -h ${DB_HOST} -u ${DB_USER} -p < ${ARQUIVO}

-- 
Mensagem automática do cron de backup (Arandu Digital)."

log "Backup concluído com sucesso."
exit 0
