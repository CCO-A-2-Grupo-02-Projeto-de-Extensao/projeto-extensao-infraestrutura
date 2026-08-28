#!/bin/bash
# Auto-converte CRLF para LF ao rodar no Linux (mantém compatibilidade Windows/Linux)
sed -i 's/\r//' "$0" 2>/dev/null || true

# =============================================================================
# Arandu — Infraestrutura AWS
# Projeto acadêmico | us-east-1
# =============================================================================

export AWS_PAGER=""
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"
set -e

# -----------------------------------------------------------------------------
# Configuração global
# -----------------------------------------------------------------------------
REGIAO="us-east-1"
VPC_CIDR="10.0.0.0/16"
VPC_NAME="vpc-arandu"
KEY_NAME="arandu-key"
ALB_NAME="alb-arandu-frontend"
TG_NAME="tg-arandu-frontend"
EFS_NAME="efs-arandu"
RDS_INSTANCE_ID="rds-arandu-db"
RDS_DB_NAME="bdClubeDesbravadores"
RDS_USERNAME="admin"
# Segredos gerados a cada provisionamento — nunca ficam versionados. Para reaproveitar
# uma stack já existente, exporte a variável antes de rodar: RDS_PASSWORD=... ./infra_arandu.sh
RDS_PASSWORD="${RDS_PASSWORD:-$(openssl rand -hex 16)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
RDS_CLASS="db.t3.micro"
RDS_ENGINE="mysql"
RDS_ENGINE_VERSION="8.0"
SQL_URL="https://raw.githubusercontent.com/CCO-A-2-Grupo-02-Projeto-de-Extensao/projeto-extensao-backend/main/bdClubeDesbravadores.sql"
TESTE_LB_SCRIPT="testar_loadbalancer.sh"
AMI_OWNER="099720109477"
AMI_FILTER="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
BACKEND_DOCKER_IMAGE="pedrobarbosa996/arandu_digital:backend"
TG_BACKEND_NAME="tg-arandu-backend"
IAM_ROLE_NAME="arandu-backend-role"
IAM_PROFILE_NAME="arandu-backend-profile"

# Subnets: name | cidr | az | public
declare -A SUBNETS=(
    [frontend-1]="subnet-frontend-publica-arandu|10.0.1.0/24|us-east-1a|true"
    [frontend-2]="subnet-frontend-publica-arandu-2|10.0.4.0/24|us-east-1b|true"
    [backend]="subnet-backend-privada-arandu|10.0.2.0/24|us-east-1a|false"
    [db]="subnet-privada-db-arandu|10.0.3.0/24|us-east-1a|false"
    [db-2]="subnet-privada-db-arandu-2|10.0.5.0/24|us-east-1b|false"
)

# -----------------------------------------------------------------------------
# Utilitários de log
# -----------------------------------------------------------------------------
ts()   { date +"%H:%M:%S"; }
log()  { echo -e "\e[32m[$(ts)] (!) $*\e[0m"; }
warn() { echo -e "\e[33m[$(ts)] (!) $*\e[0m"; }
err()  { echo -e "\e[31m[$(ts)] (!) $*\e[0m"; }

# -----------------------------------------------------------------------------
# Utilitários AWS genéricos
# -----------------------------------------------------------------------------
aws_wait() {
    local max=$1 interval=$2; shift 2
    local elapsed=0
    while [ $elapsed -lt $max ]; do
        local result
        result=$("$@" 2>/dev/null || true)
        [ -z "$result" ] && return 0
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

safe_delete() { "$@" 2>/dev/null || true; }

get_alb_arn() {
    aws elbv2 describe-load-balancers \
        --names "$1" \
        --query "LoadBalancers[0].LoadBalancerArn" \
        --output text 2>/dev/null | grep -v None || true
}

get_tg_arn() {
    aws elbv2 describe-target-groups \
        --names "$1" \
        --query "TargetGroups[0].TargetGroupArn" \
        --output text 2>/dev/null | grep -v None || true
}

# -----------------------------------------------------------------------------
# Credenciais
# -----------------------------------------------------------------------------
configurar_credenciais() {
    err "Já digitou suas credenciais de acesso nas últimas 4 horas? (s/n)"
    read -r resposta
    [[ "$resposta" == "s" || "$resposta" == "S" ]] && return
    log "Informe as credenciais temporárias da AWS."
    echo "AWS Access Key ID:"    ; read -r accessKey
    echo "AWS Secret Access Key:"; read -r secretKey
    echo "Session Token:"        ; read -r sessionToken

    aws configure set aws_access_key_id     "$accessKey"
    aws configure set aws_secret_access_key "$secretKey"
    aws configure set aws_session_token     "$sessionToken"
    aws configure set default.region        "$REGIAO"
    log "Credenciais cadastradas."
}

# -----------------------------------------------------------------------------
# Rede
# -----------------------------------------------------------------------------
criar_subnet() {
    local key=$1
    local IFS='|'; read -r name cidr az public <<< "${SUBNETS[$key]}"
    local id
    id=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$cidr" \
        --availability-zone "$az" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    [[ "$public" == "true" ]] && \
        aws ec2 modify-subnet-attribute --subnet-id "$id" --map-public-ip-on-launch
    echo "$id"
}

criar_route_table() {
    local name=$1 gateway_flag=$2 gateway_id=$3
    local rt_id
    rt_id=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    aws ec2 create-route \
        --route-table-id "$rt_id" \
        --destination-cidr-block 0.0.0.0/0 \
        "$gateway_flag" "$gateway_id" > /dev/null
    echo "$rt_id"
}

associar_subnet_rt() {
    local rt=$1; shift
    for subnet in "$@"; do
        aws ec2 associate-route-table --route-table-id "$rt" --subnet-id "$subnet" > /dev/null
    done
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
criar_sg() {
    local name=$1 desc=$2
    local id
    id=$(aws ec2 create-security-group \
        --group-name "$name" \
        --description "$desc" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)
    aws ec2 create-tags --resources "$id" --tags "Key=Name,Value=$name"
    echo "$id"
}

sg_ingress() {
    local sg=$1 proto=$2 port=$3
    if [[ "$4" == "cidr" ]]; then
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg" --protocol "$proto" --port "$port" --cidr "$5" > /dev/null
    else
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg" --protocol "$proto" --port "$port" --source-group "$5" > /dev/null
    fi
}

# -----------------------------------------------------------------------------
# NACL
# -----------------------------------------------------------------------------
criar_nacl_publica() {
    local nacl_id
    nacl_id=$(aws ec2 create-network-acl \
        --vpc-id "$VPC_ID" \
        --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=nacl-publica-arandu}]' \
        --query 'NetworkAcl.NetworkAclId' \
        --output text)

    nacl_entry() {
        local dir=$1 rule=$2 proto=$3 from=$4 to=$5 action=$6
        local port_range=""
        [[ "$proto" != "-1" ]] && port_range="--port-range From=$from,To=$to"
        aws ec2 create-network-acl-entry \
            --network-acl-id "$nacl_id" \
            "$dir" \
            --rule-number "$rule" \
            --protocol "$proto" \
            $port_range \
            --cidr-block 0.0.0.0/0 \
            --rule-action "$action" > /dev/null
    }

    nacl_entry --ingress 100 tcp  80    80    allow
    nacl_entry --ingress 110 tcp  22    22    allow
    nacl_entry --ingress 115 tcp  443   443   allow
    nacl_entry --ingress 120 tcp  2049  2049  allow
    nacl_entry --ingress 130 tcp  1024  65535 allow
    nacl_entry --egress  100 -1   0     0     allow
    echo "$nacl_id"
}

associar_nacl() {
    local nacl_id=$1; shift
    for subnet in "$@"; do
        local assoc_id
        assoc_id=$(aws ec2 describe-network-acls \
            --filters "Name=association.subnet-id,Values=$subnet" \
            --query "NetworkAcls[].Associations[?SubnetId=='$subnet'].NetworkAclAssociationId" \
            --output text)
        aws ec2 replace-network-acl-association \
            --association-id "$assoc_id" \
            --network-acl-id "$nacl_id" > /dev/null
    done
}

# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------
criar_s3() {
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    local bucket="arandu-documentos-${account_id}"

    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        log "Bucket S3 já existe: $bucket" >&2
    else
        log "Criando bucket S3: $bucket" >&2
        aws s3api create-bucket --bucket "$bucket" --region "$REGIAO" > /dev/null
        aws s3api put-public-access-block \
            --bucket "$bucket" \
            --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" > /dev/null
        log "Bucket criado e bloqueio público aplicado." >&2
    fi
    echo "$bucket"
}

deletar_s3() {
    log "Esvaziando e removendo bucket S3..."
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    local bucket="arandu-documentos-${account_id}"

    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        safe_delete aws s3 rm "s3://$bucket" --recursive
        safe_delete aws s3api delete-bucket --bucket "$bucket"
        log "Bucket $bucket removido."
    else
        warn "Bucket S3 não encontrado: $bucket"
    fi
}

# -----------------------------------------------------------------------------
# IAM — Instance Profile
# -----------------------------------------------------------------------------
obter_instance_profile() {
    local s3_bucket=$1

    if aws iam get-instance-profile --instance-profile-name "LabInstanceProfile" \
        --query "InstanceProfile.InstanceProfileName" --output text 2>/dev/null | grep -q "LabInstanceProfile"; then
        log "LabInstanceProfile detectado (AWS Academy) — reutilizando." >&2
        echo "LabInstanceProfile"
        return
    fi

    if aws iam get-instance-profile --instance-profile-name "$IAM_PROFILE_NAME" 2>/dev/null; then
        log "Instance profile $IAM_PROFILE_NAME já existe, reutilizando." >&2
        echo "$IAM_PROFILE_NAME"
        return
    fi

    log "Criando IAM role e instance profile para o backend..." >&2
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document \
            '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        > /dev/null

    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "arandu-s3-policy" \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Effect\": \"Allow\",
                \"Action\": [\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\"],
                \"Resource\": [
                    \"arn:aws:s3:::${s3_bucket}\",
                    \"arn:aws:s3:::${s3_bucket}/*\"
                ]
            }]
        }" > /dev/null

    aws iam create-instance-profile --instance-profile-name "$IAM_PROFILE_NAME" > /dev/null
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$IAM_PROFILE_NAME" \
        --role-name "$IAM_ROLE_NAME" > /dev/null

    sleep 15
    echo "$IAM_PROFILE_NAME"
}

deletar_iam_backend() {
    log "Removendo IAM role/profile do backend..."
    if [[ "$(aws iam get-instance-profile --instance-profile-name "$IAM_PROFILE_NAME" \
        --query "InstanceProfile.InstanceProfileName" --output text 2>/dev/null)" != "$IAM_PROFILE_NAME" ]]; then
        warn "Profile $IAM_PROFILE_NAME não encontrado (pode ser LabInstanceProfile), pulando."
        return
    fi

    safe_delete aws iam remove-role-from-instance-profile \
        --instance-profile-name "$IAM_PROFILE_NAME" \
        --role-name "$IAM_ROLE_NAME"
    safe_delete aws iam delete-instance-profile --instance-profile-name "$IAM_PROFILE_NAME"
    safe_delete aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "arandu-s3-policy"
    safe_delete aws iam delete-role --role-name "$IAM_ROLE_NAME"
}

# -----------------------------------------------------------------------------
# EFS
# -----------------------------------------------------------------------------
criar_efs() {
    local sg_efs=$1
    log "Criando EFS..." >&2
    local efs_id
    efs_id=$(aws efs create-file-system \
        --performance-mode generalPurpose \
        --throughput-mode bursting \
        --tags "Key=Name,Value=$EFS_NAME" \
        --query 'FileSystemId' \
        --output text)

    aws efs wait file-system-available --file-system-id "$efs_id" 2>/dev/null || \
        aws_wait 120 5 aws efs describe-file-systems \
            --file-system-id "$efs_id" \
            --query "FileSystems[?LifeCycleState!='available'].FileSystemId" \
            --output text

    log "Criando mount targets do EFS nas subnets públicas..." >&2
    for subnet in "$SUBNET_PUBLICA" "$SUBNET_PUBLICA_2"; do
        aws efs create-mount-target \
            --file-system-id "$efs_id" \
            --subnet-id "$subnet" \
            --security-groups "$sg_efs" > /dev/null
    done
    echo "$efs_id"
}

# -----------------------------------------------------------------------------
# User data — Docker + nginx
# -----------------------------------------------------------------------------
FRONTEND_DOCKER_IMAGE="pedrobarbosa996/arandu_digital:frontend"
gerar_user_data() {
    local efs_id=$1
    cat <<EOF
#!/bin/bash
until curl -4 --max-time 5 -s https://google.com > /dev/null 2>&1; do sleep 10; done
apt-get update -y
apt-get install -y docker.io nfs-common

EFS_DNS="${efs_id}.efs.${REGIAO}.amazonaws.com"
mkdir -p /mnt/efs
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 "\$EFS_DNS":/ /mnt/efs
echo "\$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab

systemctl start docker
systemctl enable docker

mkdir -p /mnt/efs/frontend
if [ ! -f /mnt/efs/frontend/.deployed ]; then
    docker pull ${FRONTEND_DOCKER_IMAGE}
    docker run --rm -v /mnt/efs/frontend:/output ${FRONTEND_DOCKER_IMAGE} sh -c "cp -r /usr/share/nginx/html/. /output/"
    touch /mnt/efs/frontend/.deployed
fi

INSTANCE_IP=\$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

mkdir -p /home/ubuntu/.ssh
cat << SSHKEY > /home/ubuntu/.ssh/arandu-key.pem
${KEY_CONTENT}
SSHKEY
chmod 400 /home/ubuntu/.ssh/arandu-key.pem
chown ubuntu:ubuntu /home/ubuntu/.ssh/arandu-key.pem

docker run -d --name frontend --restart unless-stopped -p 80:80 -e INSTANCE_IP="\$INSTANCE_IP" -v /mnt/efs/frontend:/usr/share/nginx/html:ro ${FRONTEND_DOCKER_IMAGE}
EOF
}

# -----------------------------------------------------------------------------
# Instâncias EC2
# -----------------------------------------------------------------------------
criar_instancia() {
    local name=$1 role=$2 subnet=$3 ip=$4 sg=$5 user_data_file=${6:-} iam_profile=${7:-}
    local extra_flags=()
    [[ -n "$user_data_file" ]] && extra_flags+=(--user-data "file://$user_data_file" --associate-public-ip-address)
    [[ -n "$iam_profile" ]] && extra_flags+=(--iam-instance-profile "Name=$iam_profile")

    aws ec2 run-instances \
        --image-id "$IMAGEM_ID" \
        --instance-type t3.micro \
        --key-name "$KEY_NAME" \
        --subnet-id "$subnet" \
        --private-ip-address "$ip" \
        --security-group-ids "$sg" \
        "${extra_flags[@]}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name},{Key=Role,Value=$role}]" \
        --query 'Instances[0].InstanceId' \
        --output text
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------
criar_alb() {
    local sg_alb=$1 inst1=$2 inst2=$3
    log "Removendo ALB/TG antigos com o mesmo nome, se existirem..." >&2

    local old_alb=$(get_alb_arn "$ALB_NAME")
    if [[ -n "$old_alb" ]]; then
        safe_delete aws elbv2 delete-load-balancer --load-balancer-arn "$old_alb"
        safe_delete aws elbv2 wait load-balancers-deleted --load-balancer-arns "$old_alb"
    fi

    local old_tg=$(get_tg_arn "$TG_NAME")
    if [[ -n "$old_tg" ]]; then
        safe_delete aws elbv2 delete-target-group --target-group-arn "$old_tg"
    fi

    log "Criando Load Balancer..." >&2
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_PUBLICA" "$SUBNET_PUBLICA_2" \
        --security-groups "$sg_alb" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags "Key=Name,Value=$ALB_NAME" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)

    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$VPC_ID" \
        --target-type instance \
        --health-check-protocol HTTP \
        --health-check-path "/" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)

    aws elbv2 register-targets \
        --target-group-arn "$tg_arn" \
        --targets "Id=$inst1,Port=80" "Id=$inst2,Port=80" > /dev/null

    ALB_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions "Type=forward,TargetGroupArn=$tg_arn" \
        --query 'Listeners[0].ListenerArn' \
        --output text)

    local dns
    dns=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)

    safe_delete aws elbv2 wait target-in-service \
        --target-group-arn "$tg_arn" \
        --targets "Id=$inst1,Port=80" "Id=$inst2,Port=80"

    ALB_DNS="$dns"
}

# -----------------------------------------------------------------------------
# Backend — Target Group + regras Swagger
# -----------------------------------------------------------------------------
configurar_backend_alb() {
    local backend_id=$1
    log "Criando Target Group do backend..." >&2

    local old_tg_backend=$(get_tg_arn "$TG_BACKEND_NAME")
    [[ -n "$old_tg_backend" ]] && safe_delete aws elbv2 delete-target-group --target-group-arn "$old_tg_backend"

    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$TG_BACKEND_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type instance \
        --health-check-protocol HTTP \
        --health-check-path "/v3/api-docs" \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 5 \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)

    aws elbv2 register-targets \
        --target-group-arn "$tg_arn" \
        --targets "Id=$backend_id,Port=8080" > /dev/null

    local priority=10
    # Tudo que não casar com esta lista vai para o target group do frontend, e o
    # nginx devolve o index.html da SPA com status 200 — o axios não trata como
    # erro e a tela quebra. Controller novo exige entrada nova aqui.
    for path in "/swagger-ui*" "/v3/api-docs*" "/auth*" "/usuarios*" "/documentos*" \
                "/comorbidades*" "/diagnosticos*" "/fichas-medicas*" \
                "/medicacoes*" "/medicamentos*" \
                "/pessoas*" "/ocorrencias*" "/unidades*" "/generos*" \
                "/classes*" "/cargos*" "/especialidades*" "/turmas*" \
                "/chamadas*" "/eventos*" "/presencas*"; do
        aws elbv2 create-rule \
            --listener-arn "$ALB_LISTENER_ARN" \
            --conditions "[{\"Field\":\"path-pattern\",\"Values\":[\"$path\"]}]" \
            --priority $priority \
            --actions "Type=forward,TargetGroupArn=$tg_arn" > /dev/null
        priority=$((priority + 10))
    done
    log "ALB roteado: Swagger, /auth*, /usuarios*, /documentos* e demais APIs → backend" >&2
}

# -----------------------------------------------------------------------------
# Script de teste LB
# -----------------------------------------------------------------------------
gerar_script_teste() {
    local url=$1
    cat <<EOF > "$TESTE_LB_SCRIPT"
#!/bin/bash
URL="$url"
TOTAL_TESTES=20
INTERVALO=2
echo "Testando Load Balancer: \$URL"
echo "Total de testes: \$TOTAL_TESTES"
echo
for i in \$(seq 1 \$TOTAL_TESTES); do
    echo "Teste \$i..."
    SERVIDOR=\$(curl -s --max-time 10 "\$URL/hostname")
    if [ -z "\$SERVIDOR" ]; then
        echo "Sem resposta do Load Balancer"
    else
        echo "Caiu na instância: \$SERVIDOR"
    fi
    echo "----------------------------------------"
    sleep \$INTERVALO
done
EOF
    chmod +x "$TESTE_LB_SCRIPT"
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------
criar_rds() {
    local sg_db=$1 subnet_db=$2 subnet_db_2=$3
    log "Criando Subnet Group do RDS..." >&2
    aws rds create-db-subnet-group \
        --db-subnet-group-name "rds-subnet-group-arandu" \
        --db-subnet-group-description "Subnet group do RDS Arandu" \
        --subnet-ids "$subnet_db" "$subnet_db_2" > /dev/null

    log "Criando instância RDS MySQL..." >&2
    aws rds create-db-instance \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --db-instance-class "$RDS_CLASS" \
        --engine "$RDS_ENGINE" \
        --engine-version "$RDS_ENGINE_VERSION" \
        --master-username "$RDS_USERNAME" \
        --master-user-password "$RDS_PASSWORD" \
        --db-name "$RDS_DB_NAME" \
        --vpc-security-group-ids "$sg_db" \
        --db-subnet-group-name "rds-subnet-group-arandu" \
        --no-publicly-accessible \
        --allocated-storage 20 \
        --storage-type gp2 \
        --backup-retention-period 0 \
        --no-multi-az \
        --no-deletion-protection > /dev/null

    log "Aguardando RDS ficar disponível (pode levar ~5 min)..." >&2
    aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE_ID"

    aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query "DBInstances[0].Endpoint.Address" \
        --output text
}

gerar_user_data_backend() {
    local rds_endpoint=$1 s3_bucket=$2
    cat <<EOF
#!/bin/bash
until curl -4 --max-time 5 -s https://google.com > /dev/null 2>&1; do sleep 10; done
apt-get update -y
apt-get install -y mysql-client curl docker.io

until mysql -h "${rds_endpoint}" -u "${RDS_USERNAME}" -p"${RDS_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; do sleep 15; done

curl -4 -s "${SQL_URL}" -o /tmp/bdClubeDesbravadores.sql
mysql -h "${rds_endpoint}" -u "${RDS_USERNAME}" -p"${RDS_PASSWORD}" "${RDS_DB_NAME}" < /tmp/bdClubeDesbravadores.sql
rm -f /tmp/bdClubeDesbravadores.sql

systemctl start docker
systemctl enable docker
docker pull ${BACKEND_DOCKER_IMAGE}
docker run -d --name backend --restart unless-stopped -p 8080:8080 -e SPRING_DATASOURCE_URL="jdbc:mysql://${rds_endpoint}:3306/${RDS_DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC" -e SPRING_DATASOURCE_USERNAME="${RDS_USERNAME}" -e SPRING_DATASOURCE_PASSWORD="${RDS_PASSWORD}" -e JWT_SECRET="${JWT_SECRET}" -e APP_STORAGE_TYPE="s3" -e APP_STORAGE_S3_BUCKET="${s3_bucket}" -e APP_STORAGE_S3_REGION="${REGIAO}" ${BACKEND_DOCKER_IMAGE}
EOF
}

deletar_rds() {
    log "Removendo instância RDS..."
    safe_delete aws rds delete-db-instance --db-instance-identifier "$RDS_INSTANCE_ID" --skip-final-snapshot
    safe_delete aws rds wait db-instance-deleted --db-instance-identifier "$RDS_INSTANCE_ID"
    log "Removendo Subnet Group do RDS..."
    safe_delete aws rds delete-db-subnet-group --db-subnet-group-name "rds-subnet-group-arandu"
}

# -----------------------------------------------------------------------------
# Observabilidade (CloudWatch e Cost Explorer)
# -----------------------------------------------------------------------------
criar_dashboard_cloudwatch() {
    log "Criando Dashboard no CloudWatch (Arandu-Dashboard)..."
    local dashboard_name="Arandu-Dashboard"

    local alb_suffix
    alb_suffix=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null \
        | awk -F':loadbalancer/' '{print $2}')

    if [[ -z "$alb_suffix" ]]; then
        warn "Nao foi possivel obter o ARN do ALB — dashboard criado sem metricas de ALB."
    fi

    # Gera JSON via python3 com ensure_ascii=True para evitar bugs de encoding
    # com caracteres acentuados em ambientes sem UTF-8 configurado corretamente.
    local dashboard_body
    dashboard_body=$(python3 - "$REGIAO" "$FRONTEND_1_ID" "$FRONTEND_2_ID" \
                              "$BACKEND_ID" "$RDS_INSTANCE_ID" "$alb_suffix" <<'PYEOF'
import json, sys

r, fe1, fe2, be, rds, alb = sys.argv[1:]

def metric(ns, name, dim_key, dim_val, **props):
    entry = [ns, name, dim_key, dim_val]
    if props:
        entry.append(props)
    return entry

widgets = [
    # ── Cabecalho ──────────────────────────────────────────────────────────
    {
        "type": "text",
        "x": 0, "y": 0, "width": 24, "height": 2,
        "properties": {
            "markdown": (
                "# Arandu Digital — Monitoramento de Infraestrutura\n"
                "Dashboard gerado automaticamente | Regiao: **" + r + "**"
            )
        }
    },
    # ── CPU EC2 ────────────────────────────────────────────────────────────
    {
        "type": "metric",
        "x": 0, "y": 2, "width": 12, "height": 6,
        "properties": {
            "title": "CPU das Instancias EC2 (%)",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/EC2", "CPUUtilization", "InstanceId", fe1, {"label": "Frontend 1", "color": "#1f77b4"}],
                [".",       ".",              ".",          fe2, {"label": "Frontend 2", "color": "#ff7f0e"}],
                [".",       ".",              ".",          be,  {"label": "Backend",    "color": "#2ca02c"}],
            ],
            "annotations": {
                "horizontal": [{"label": "Alerta 80%", "value": 80, "color": "#d62728", "fill": "above"}]
            },
            "yAxis": {"left": {"min": 0, "max": 100, "label": "%"}}
        }
    },
    # ── Requisicoes e Saude ALB ────────────────────────────────────────────
    {
        "type": "metric",
        "x": 12, "y": 2, "width": 12, "height": 6,
        "properties": {
            "title": "Requisicoes e Hosts Saudaveis (ALB)",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/ApplicationELB", "RequestCount",    "LoadBalancer", alb,
                 {"stat": "Sum",     "label": "Requisicoes (sum)",  "color": "#1f77b4"}],
                [".",                  "HealthyHostCount",".",        alb,
                 {"stat": "Average", "label": "Hosts saudaveis",    "color": "#2ca02c", "yAxis": "right"}],
            ],
            "yAxis": {
                "left":  {"label": "Requisicoes", "min": 0},
                "right": {"label": "Hosts",       "min": 0}
            }
        }
    },
    # ── Erros 5xx ALB ─────────────────────────────────────────────────────
    {
        "type": "metric",
        "x": 0, "y": 8, "width": 8, "height": 6,
        "properties": {
            "title": "Erros 5xx (ALB)",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", alb,
                 {"stat": "Sum", "label": "5xx Target", "color": "#d62728"}],
                [".",                  "HTTPCode_ELB_5XX_Count",    ".",             alb,
                 {"stat": "Sum", "label": "5xx ELB",    "color": "#ff7f0e"}],
            ],
            "annotations": {
                "horizontal": [{"label": "Limite", "value": 10, "color": "#d62728"}]
            },
            "yAxis": {"left": {"min": 0}}
        }
    },
    # ── Erros 4xx ALB ─────────────────────────────────────────────────────
    {
        "type": "metric",
        "x": 8, "y": 8, "width": 8, "height": 6,
        "properties": {
            "title": "Erros 4xx (ALB)",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", alb,
                 {"stat": "Sum", "label": "4xx Target", "color": "#ff7f0e"}],
                [".",                  "HTTPCode_ELB_4XX_Count",    ".",             alb,
                 {"stat": "Sum", "label": "4xx ELB",    "color": "#ffbb78"}],
            ],
            "yAxis": {"left": {"min": 0}}
        }
    },
    # ── Latencia ALB ───────────────────────────────────────────────────────
    {
        "type": "metric",
        "x": 16, "y": 8, "width": 8, "height": 6,
        "properties": {
            "title": "Latencia de Resposta (ALB)",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", alb,
                 {"stat": "p50", "label": "p50", "color": "#2ca02c"}],
                [".",                  ".",                  ".",             alb,
                 {"stat": "p90", "label": "p90", "color": "#ff7f0e"}],
                [".",                  ".",                  ".",             alb,
                 {"stat": "p99", "label": "p99", "color": "#d62728"}],
            ],
            "annotations": {
                "horizontal": [{"label": "SLA 1s", "value": 1, "color": "#d62728"}]
            },
            "yAxis": {"left": {"min": 0, "label": "segundos"}}
        }
    },
    # ── RDS CPU e Conexoes ─────────────────────────────────────────────────
    {
        "type": "metric",
        "x": 0, "y": 14, "width": 8, "height": 6,
        "properties": {
            "title": "RDS — CPU e Conexoes",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/RDS", "CPUUtilization",     "DBInstanceIdentifier", rds,
                 {"label": "CPU (%)",  "color": "#1f77b4", "yAxis": "left"}],
                [".",       "DatabaseConnections", ".",                    rds,
                 {"label": "Conexoes", "color": "#ff7f0e", "yAxis": "right"}],
            ],
            "yAxis": {
                "left":  {"label": "CPU (%)",  "min": 0, "max": 100},
                "right": {"label": "Conexoes", "min": 0}
            }
        }
    },
    # ── RDS Armazenamento e Memoria ────────────────────────────────────────
    {
        "type": "metric",
        "x": 8, "y": 14, "width": 8, "height": 6,
        "properties": {
            "title": "RDS — Storage e Memoria Livre",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 300,
            "metrics": [
                ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", rds,
                 {"stat": "Minimum", "label": "Storage Livre", "color": "#2ca02c"}],
                [".",       "FreeableMemory",   ".",                    rds,
                 {"stat": "Minimum", "label": "Memoria Livre", "color": "#17becf"}],
            ],
            "yAxis": {"left": {"min": 0, "label": "bytes"}}
        }
    },
    # ── RDS Latencia ───────────────────────────────────────────────────────
    {
        "type": "metric",
        "x": 16, "y": 14, "width": 8, "height": 6,
        "properties": {
            "title": "RDS — Latencia de Leitura e Escrita",
            "view": "timeSeries", "stacked": False,
            "region": r, "period": 60,
            "metrics": [
                ["AWS/RDS", "ReadLatency",  "DBInstanceIdentifier", rds,
                 {"stat": "Average", "label": "Leitura",  "color": "#1f77b4"}],
                [".",       "WriteLatency", ".",                    rds,
                 {"stat": "Average", "label": "Escrita",  "color": "#ff7f0e"}],
            ],
            "yAxis": {"left": {"min": 0, "label": "segundos"}}
        }
    },
]

print(json.dumps({"widgets": widgets}, ensure_ascii=True))
PYEOF
)

    if [[ -z "$dashboard_body" ]]; then
        err "Falha ao gerar o JSON do dashboard via python3."
        return 1
    fi

    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body "$dashboard_body" > /dev/null

    DASHBOARD_URL="https://${REGIAO}.console.aws.amazon.com/cloudwatch/home?region=${REGIAO}#dashboards/dashboard/${dashboard_name}"
}

deletar_dashboard_cloudwatch() {
    log "Removendo Dashboard do CloudWatch..."
    safe_delete aws cloudwatch delete-dashboards --dashboard-names "Arandu-Dashboard"
}

consultar_custos() {
    log "Consultando custos do mês atual via AWS Cost Explorer..."
    local start_date=$(date +%Y-%m-01)
    local end_date=$(date +%Y-%m-%d)

    if [[ "$start_date" == "$end_date" ]]; then
        end_date=$(date -d "+1 day" +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d)
    fi

    local custo=$(aws ce get-cost-and-usage \
        --time-period Start=$start_date,End=$end_date \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --query 'ResultsByTime[0].Total.UnblendedCost.Amount' \
        --output text 2>/dev/null || echo "inativo")

    if [[ "$custo" != "inativo" && -n "$custo" ]]; then
        log "Custo estimado acumulado ($start_date a $end_date): \$ $(printf "%.2f" "$custo") USD"
    else
        warn "Cost Explorer inativo ou sem permissão. Ative em: https://us-east-1.console.aws.amazon.com/cost-management/home"
    fi
}

# -----------------------------------------------------------------------------
# Limpeza — recursos dentro da VPC
# -----------------------------------------------------------------------------
deletar_instancias() {
    log "Encerrando instâncias..."
    local ids=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || true)
    if [[ -z "$ids" ]]; then warn "Nenhuma instância encontrada."; return; fi
    safe_delete aws ec2 terminate-instances --instance-ids $ids
    safe_delete aws ec2 wait instance-terminated --instance-ids $ids
}

deletar_albs() {
    log "Removendo Load Balancers..."
    local arns=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true)
    for arn in $arns; do
        safe_delete aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
        safe_delete aws elbv2 wait load-balancers-deleted --load-balancer-arns "$arn"
    done
    local tg_arns=$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" --output text 2>/dev/null || true)
    for arn in $tg_arns; do safe_delete aws elbv2 delete-target-group --target-group-arn "$arn"; done

    local old_alb=$(get_alb_arn "$ALB_NAME")
    if [[ -n "$old_alb" ]]; then
        safe_delete aws elbv2 delete-load-balancer --load-balancer-arn "$old_alb"
        safe_delete aws elbv2 wait load-balancers-deleted --load-balancer-arns "$old_alb"
    fi
    local old_tg=$(get_tg_arn "$TG_NAME")
    if [[ -n "$old_tg" ]]; then safe_delete aws elbv2 delete-target-group --target-group-arn "$old_tg"; fi

    log "Aguardando ENIs do ALB serem liberadas..."
    aws_wait 120 10 aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=ELB*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || true
}

deletar_efs() {
    log "Removendo EFS..."
    local efs_ids=$(aws efs describe-file-systems --query "FileSystems[?Tags[?Key=='Name'&&Value=='$EFS_NAME']].FileSystemId" --output text 2>/dev/null || true)
    for efs_id in $efs_ids; do
        local mt_ids=$(aws efs describe-mount-targets --file-system-id "$efs_id" --query "MountTargets[].MountTargetId" --output text 2>/dev/null || true)
        for mt in $mt_ids; do safe_delete aws efs delete-mount-target --mount-target-id "$mt"; done
        aws_wait 120 10 aws efs describe-mount-targets --file-system-id "$efs_id" --query "MountTargets[].MountTargetId" --output text 2>/dev/null || true
        safe_delete aws efs delete-file-system --file-system-id "$efs_id"
    done
}

deletar_nat() {
    log "Removendo NAT Gateway..."
    local nat_ids=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[?State!='deleted'].NatGatewayId" --output text 2>/dev/null || true)
    for nat in $nat_ids; do
        local eip=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$nat" --query "NatGateways[0].NatGatewayAddresses[0].AllocationId" --output text 2>/dev/null || true)
        safe_delete aws ec2 delete-nat-gateway --nat-gateway-id "$nat"
        safe_delete aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat"
        if [[ "$eip" != "None" && -n "$eip" ]]; then safe_delete aws ec2 release-address --allocation-id "$eip"; fi
    done
}

deletar_route_tables() {
    log "Removendo tabelas de rota..."
    local rts=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[?length(Associations[?Main==\`true\`]) == \`0\`].RouteTableId" --output text 2>/dev/null || true)
    for rt in $rts; do
        local assocs=$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[].Associations[?Main==\false\].RouteTableAssociationId" --output text 2>/dev/null || true)
        for assoc in $assocs; do safe_delete aws ec2 disassociate-route-table --association-id "$assoc"; done
        safe_delete aws ec2 delete-route-table --route-table-id "$rt"
    done
}

deletar_igw() {
    log "Removendo Internet Gateway..."
    local igws=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text 2>/dev/null || true)
    for igw in $igws; do
        safe_delete aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
        safe_delete aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    done
}

deletar_nacls() {
    log "Removendo NACLs customizadas..."
    local default_nacl=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" --query "NetworkAcls[0].NetworkAclId" --output text 2>/dev/null || true)
    local custom_nacls=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkAcls[?IsDefault==\false\].NetworkAclId" --output text 2>/dev/null || true)
    for nacl in $custom_nacls; do
        local assocs=$(aws ec2 describe-network-acls --network-acl-ids "$nacl" --query "NetworkAcls[].Associations[].NetworkAclAssociationId" --output text 2>/dev/null || true)
        for assoc in $assocs; do
            if [[ "$default_nacl" != "None" && -n "$default_nacl" ]]; then
                safe_delete aws ec2 replace-network-acl-association --association-id "$assoc" --network-acl-id "$default_nacl"
            fi
        done
        safe_delete aws ec2 delete-network-acl --network-acl-id "$nacl"
    done
}

deletar_subnets() {
    log "Removendo subnets..."
    local subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[].SubnetId" --output text 2>/dev/null || true)
    for s in $subnets; do safe_delete aws ec2 delete-subnet --subnet-id "$s"; done
}

deletar_enis() {
    log "Aguardando e removendo interfaces de rede restantes..."
    aws_wait 180 15 aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || true
    local enis=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || true)
    for eni in $enis; do
        local att=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni" --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || true)
        if [[ "$att" != "None" && -n "$att" ]]; then safe_delete aws ec2 detach-network-interface --attachment-id "$att" --force; fi
        safe_delete aws ec2 delete-network-interface --network-interface-id "$eni"
    done
}

deletar_security_groups() {
    log "Removendo Security Groups..."
    local sgs=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || true)
    for sg in $sgs; do
        local ingress=$(aws ec2 describe-security-groups --group-ids "$sg" --query "SecurityGroups[].IpPermissions" --output json 2>/dev/null || echo "[]")
        local egress=$(aws ec2 describe-security-groups --group-ids "$sg" --query "SecurityGroups[].IpPermissionsEgress" --output json 2>/dev/null || echo "[]")
        if [[ "$ingress" != "[]" ]]; then safe_delete aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$ingress"; fi
        if [[ "$egress" != "[]" ]]; then safe_delete aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions "$egress"; fi
    done
    sleep 10
    for sg in $sgs; do safe_delete aws ec2 delete-security-group --group-id "$sg"; done
}

mostrar_dependencias_vpc() {
    warn "Dependências restantes na VPC $VPC_ID:"
    for recurso in \
        "Subnets|aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query Subnets[].SubnetId --output text" \
        "ENIs|aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC_ID --query NetworkInterfaces[].NetworkInterfaceId --output text" \
        "SGs|aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query SecurityGroups[?GroupName!='default'].GroupId --output text" \
        "Route Tables|aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query RouteTables[].RouteTableId --output text" \
        "IGWs|aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query InternetGateways[].InternetGatewayId --output text"
    do
        local label="${recurso%%|*}"
        local cmd="${recurso##*|}"
        local result=$(eval "$cmd" 2>/dev/null || true)
        echo "  $label: ${result:-nenhum}"
    done
}

deletar_vpc() {
    log "Deletando VPC..."
    for tentativa in 1 2 3; do
        log "Tentativa $tentativa de limpeza final..."
        deletar_efs
        deletar_route_tables
        deletar_nacls
        deletar_enis
        deletar_subnets
        deletar_security_groups
        sleep 30
        if aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null; then log "VPC deletada com sucesso!"; return 0; fi
        warn "VPC ainda não deletada. Tentando novamente em 30s..."
        sleep 30
    done
    err "Não foi possível deletar a VPC. Dependências restantes:"
    mostrar_dependencias_vpc
    warn "Aguarde alguns minutos e rode a opção 2 novamente."
    return 1
}

# -----------------------------------------------------------------------------
# Fluxo principal — Criação
# -----------------------------------------------------------------------------
criar_infraestrutura() {
    log "Criando VPC..."
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "$VPC_CIDR" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query 'Vpc.VpcId' \
        --output text)
    aws ec2 wait vpc-available --vpc-ids "$VPC_ID"

    log "Criando subnets..."
    SUBNET_PUBLICA=$(criar_subnet frontend-1)
    SUBNET_PUBLICA_2=$(criar_subnet frontend-2)
    SUBNET_PRIVADA=$(criar_subnet backend)
    SUBNET_DB=$(criar_subnet db)
    SUBNET_DB_2=$(criar_subnet db-2)

    log "Criando Internet Gateway..."
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=internet-gateway-arandu}]' \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

    log "Criando tabelas de rota..."
    RT_PUBLICA=$(criar_route_table "rota-publica-arandu" --gateway-id "$IGW_ID")
    associar_subnet_rt "$RT_PUBLICA" "$SUBNET_PUBLICA" "$SUBNET_PUBLICA_2"

    log "Criando NAT Gateway..."
    EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
    NAT_ID=$(aws ec2 create-nat-gateway \
        --subnet-id "$SUBNET_PUBLICA" \
        --allocation-id "$EIP_ID" \
        --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=nat-arandu}]' \
        --query 'NatGateway.NatGatewayId' \
        --output text)
    aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

    RT_PRIVADA=$(criar_route_table "rota-privada-arandu" --nat-gateway-id "$NAT_ID")
    associar_subnet_rt "$RT_PRIVADA" "$SUBNET_PRIVADA" "$SUBNET_DB" "$SUBNET_DB_2"

    log "Criando NACL pública..."
    NACL_ID=$(criar_nacl_publica)
    associar_nacl "$NACL_ID" "$SUBNET_PUBLICA" "$SUBNET_PUBLICA_2"

    log "Criando Security Groups..."
    SG_ALB=$(criar_sg "arandu-sg-alb" "SG Load Balancer Arandu")
    sg_ingress "$SG_ALB"      tcp 80   cidr   0.0.0.0/0
    SG_FRONTEND=$(criar_sg "arandu-sg-frontend" "SG Frontend Arandu")
    sg_ingress "$SG_FRONTEND" tcp 22   cidr   0.0.0.0/0
    sg_ingress "$SG_FRONTEND" tcp 80   sg     "$SG_ALB"
    SG_EFS=$(criar_sg "arandu-sg-efs" "SG EFS Arandu")
    sg_ingress "$SG_EFS"      tcp 2049 sg     "$SG_FRONTEND"
    SG_BACKEND=$(criar_sg "arandu-sg-backend" "SG Backend Arandu")
    sg_ingress "$SG_BACKEND"  tcp 8080 sg     "$SG_FRONTEND"
    sg_ingress "$SG_BACKEND"  tcp 8080 sg     "$SG_ALB"
    sg_ingress "$SG_BACKEND"  tcp 22   sg     "$SG_FRONTEND"
    SG_DB=$(criar_sg "arandu-sg-db" "SG Database Arandu")
    sg_ingress "$SG_DB"       tcp 3306 sg     "$SG_BACKEND"
    sg_ingress "$SG_DB"       tcp 22   sg     "$SG_BACKEND"

    log "Buscando AMI Ubuntu..."
    IMAGEM_ID=$(aws ec2 describe-images \
        --owners "$AMI_OWNER" \
        --filters "Name=name,Values=$AMI_FILTER" \
        --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
        --output text)

    log "Criando chave SSH..."
    safe_delete aws ec2 delete-key-pair --key-name "$KEY_NAME"
    rm -f arandu-key.pem
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --key-type rsa \
        --query 'KeyMaterial' \
        --output text > arandu-key.pem
    chmod 400 arandu-key.pem

    EFS_ID=$(criar_efs "$SG_EFS")

    log "Gerando user data do Nginx + EFS..."
    KEY_CONTENT=$(cat arandu-key.pem) gerar_user_data "$EFS_ID" > user_data_nginx.sh

    log "Criando instâncias frontend..."
    FRONTEND_1_ID=$(criar_instancia ec2-arandu-frontend-1 frontend "$SUBNET_PUBLICA"   10.0.1.10 "$SG_FRONTEND" user_data_nginx.sh)
    FRONTEND_2_ID=$(criar_instancia ec2-arandu-frontend-2 frontend "$SUBNET_PUBLICA_2" 10.0.4.10 "$SG_FRONTEND" user_data_nginx.sh)
    aws ec2 wait instance-running --instance-ids "$FRONTEND_1_ID" "$FRONTEND_2_ID"
    criar_alb "$SG_ALB" "$FRONTEND_1_ID" "$FRONTEND_2_ID"

    APP_DNS="$ALB_DNS"
    APP_URL="http://$APP_DNS"

    log "Criando bucket S3..."
    S3_BUCKET=$(criar_s3)

    log "Obtendo instance profile IAM para o backend..."
    BACKEND_PROFILE=$(obter_instance_profile "$S3_BUCKET")

    log "Criando RDS MySQL..."
    RDS_ENDPOINT=$(criar_rds "$SG_DB" "$SUBNET_DB" "$SUBNET_DB_2")

    log "Gerando user data do backend..."
    gerar_user_data_backend "$RDS_ENDPOINT" "$S3_BUCKET" > user_data_backend.sh

    log "Criando instância backend..."
    BACKEND_ID=$(criar_instancia ec2-arandu-backend backend "$SUBNET_PRIVADA" 10.0.2.10 "$SG_BACKEND" user_data_backend.sh "$BACKEND_PROFILE")
    aws ec2 wait instance-running --instance-ids "$BACKEND_ID"

    log "Configurando roteamento Swagger no ALB..."
    configurar_backend_alb "$BACKEND_ID"

    gerar_script_teste "$APP_URL"
    rm -f user_data_nginx.sh user_data_backend.sh

    log "Configurando Observabilidade..."
    criar_dashboard_cloudwatch

    echo ""
    log "Infraestrutura criada com sucesso!"
    log "EFS ID:             $EFS_ID"
    log "Frontend (EFS):     /mnt/efs/frontend  ← servido pelas 2 instâncias"
    log "Frontend imagem:    $FRONTEND_DOCKER_IMAGE"
    log "S3 Bucket:          $S3_BUCKET"
    log "RDS Endpoint:       $RDS_ENDPOINT"
    log "RDS Database:       $RDS_DB_NAME"
    log "RDS User:           $RDS_USERNAME"
    log "RDS Password:       $RDS_PASSWORD  ← gerada agora, anote se for conectar no banco"
    log "URL da aplicação:   $APP_URL"
    log "Swagger:            $APP_URL/swagger-ui/index.html"
    log "CloudWatch Dash:    $DASHBOARD_URL"
    log "Teste do balanceador: ./$TESTE_LB_SCRIPT"
    warn "Se abrir antes dos targets ficarem saudáveis, aguarde alguns instantes e atualize a página."
}

# -----------------------------------------------------------------------------
# Fluxo principal — Deleção
# -----------------------------------------------------------------------------
deletar_infraestrutura() {
    deletar_dashboard_cloudwatch
    deletar_instancias
    deletar_rds
    deletar_albs
    deletar_efs
    deletar_nat
    deletar_route_tables
    deletar_igw
    deletar_nacls
    deletar_subnets
    deletar_enis
    deletar_security_groups
    deletar_s3
    deletar_iam_backend

    log "Removendo arquivos locais..."
    safe_delete aws ec2 delete-key-pair --key-name "$KEY_NAME"
    rm -f arandu-key.pem "$TESTE_LB_SCRIPT"
    deletar_vpc
}

# =============================================================================
# Entry point
# =============================================================================
clear
echo -e "\n\n\n"
configurar_credenciais

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query "Vpcs[0].VpcId" \
    --output text 2>/dev/null | grep -v None || true)

if [[ -z "$VPC_ID" ]]; then
    log "VPC não encontrada. Criando infraestrutura..."
    criar_infraestrutura
else
    err "VPC já existe: $VPC_ID"
    echo "1 - Manter infraestrutura"
    echo "2 - Deletar TUDO da VPC"
    echo "3 - Consultar Custos (AWS Cost Explorer)"
    read -r opcao

    if [[ "$opcao" == "2" ]]; then
        deletar_infraestrutura
    elif [[ "$opcao" == "3" ]]; then
        consultar_custos
    fi
fi