#!/bin/bash

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
TESTE_LB_SCRIPT="testar_loadbalancer.sh"
AMI_OWNER="099720109477"
AMI_FILTER="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"

# Subnets: name | cidr | az | public
declare -A SUBNETS=(
    [frontend-1]="subnet-frontend-publica-arandu|10.0.1.0/24|us-east-1a|true"
    [frontend-2]="subnet-frontend-publica-arandu-2|10.0.4.0/24|us-east-1b|true"
    [backend]="subnet-backend-privada-arandu|10.0.2.0/24|us-east-1a|false"
    [db]="subnet-privada-db-arandu|10.0.3.0/24|us-east-1a|false"
)

# -----------------------------------------------------------------------------
# Utilitários de log
# -----------------------------------------------------------------------------
log()  { echo -e "\e[32m(!) $*\e[0m"; }
warn() { echo -e "\e[33m(!) $*\e[0m"; }
err()  { echo -e "\e[31m(!) $*\e[0m"; }

# -----------------------------------------------------------------------------
# Utilitários AWS genéricos
# -----------------------------------------------------------------------------

# Aguarda até que uma condição seja verdadeira (evita sleeps fixos)
# Uso: aws_wait <segundos_max> <intervalo> <cmd_que_retorna_vazio_quando_pronto>
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

# Deleta um recurso somente se ele existir; silencia erros
# Nunca propaga código de saída diferente de zero — seguro com set -e
safe_delete() { "$@" 2>/dev/null || true; }

# Retorna o ARN do ALB pelo nome, ou vazio
get_alb_arn() {
    aws elbv2 describe-load-balancers \
        --names "$1" \
        --query "LoadBalancers[0].LoadBalancerArn" \
        --output text 2>/dev/null | grep -v None || true
}

# Retorna o ARN do Target Group pelo nome, ou vazio
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

# Autoriza uma regra de ingresso por CIDR ou por source-group
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

    # Função interna para criar entradas NACL — evita repetir todos os flags
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
    nacl_entry --ingress 120 tcp  2049  2049  allow  # NFS para EFS
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
# EFS
# -----------------------------------------------------------------------------
criar_efs() {
    local sg_efs=$1

    log "Criando EFS..."
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

    log "Criando mount targets do EFS nas subnets públicas..."
    for subnet in "$SUBNET_PUBLICA" "$SUBNET_PUBLICA_2"; do
        aws efs create-mount-target \
            --file-system-id "$efs_id" \
            --subnet-id "$subnet" \
            --security-groups "$sg_efs" > /dev/null
    done

    echo "$efs_id"
}

# -----------------------------------------------------------------------------
# User data — Nginx + montagem do EFS
# -----------------------------------------------------------------------------
gerar_user_data() {
    local efs_id=$1
    cat <<EOF
#!/bin/bash
apt-get update -y
apt-get install -y nginx nfs-common

EFS_DNS="${efs_id}.efs.${REGIAO}.amazonaws.com"
mkdir -p /mnt/efs
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
    "\$EFS_DNS":/ /mnt/efs
echo "\$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab

HOSTNAME_ATUAL=\$(hostname)

cat <<HTML > /var/www/html/index.html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Arandu Frontend</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f4f7fb; color: #1f2937;
               display: flex; justify-content: center; align-items: center;
               height: 100vh; margin: 0; }
        .card { background: white; padding: 32px; border-radius: 12px;
                box-shadow: 0 8px 24px rgba(0,0,0,0.12); text-align: center; }
        h1 { margin-bottom: 8px; color: #2563eb; }
        p  { margin: 6px 0; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Frontend Arandu</h1>
        <p>Instância EC2 com Nginx funcionando.</p>
        <p>Balanceamento de carga ativo.</p>
        <p>EFS montado em <strong>/mnt/efs</strong></p>
        <p><strong>Servidor:</strong> \$HOSTNAME_ATUAL</p>
    </div>
</body>
</html>
HTML

systemctl start nginx
systemctl enable nginx
EOF
}

# -----------------------------------------------------------------------------
# Instâncias EC2
# -----------------------------------------------------------------------------
criar_instancia() {
    local name=$1 role=$2 subnet=$3 ip=$4 sg=$5 user_data_file=${6:-}

    local extra_flags=()
    [[ -n "$user_data_file" ]] && extra_flags+=(--user-data "file://$user_data_file" --associate-public-ip-address)

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

    log "Removendo ALB/TG antigos com o mesmo nome, se existirem..."
    local old_alb
    old_alb=$(get_alb_arn "$ALB_NAME")
    if [[ -n "$old_alb" ]]; then
        safe_delete aws elbv2 delete-load-balancer --load-balancer-arn "$old_alb"
        safe_delete aws elbv2 wait load-balancers-deleted --load-balancer-arns "$old_alb"
    fi

    local old_tg
    old_tg=$(get_tg_arn "$TG_NAME")
    if [[ -n "$old_tg" ]]; then
        safe_delete aws elbv2 delete-target-group --target-group-arn "$old_tg"
    fi

    log "Criando Load Balancer..."
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

    aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions "Type=forward,TargetGroupArn=$tg_arn" > /dev/null

    local dns
    dns=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)

    safe_delete aws elbv2 wait target-in-service \
        --target-group-arn "$tg_arn" \
        --targets "Id=$inst1,Port=80" "Id=$inst2,Port=80"

    echo "$dns"
}

# -----------------------------------------------------------------------------
# Script de teste do Load Balancer (gerado dinamicamente)
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
    RESPOSTA=\$(curl -s --max-time 10 "\$URL")

    if [ -z "\$RESPOSTA" ]; then
        echo "Sem resposta do Load Balancer"
    else
        SERVIDOR=\$(echo "\$RESPOSTA" | sed -n 's/.*<strong>Servidor:<\/strong> \([^<]*\)<\/p>.*/\1/p')
        [ -n "\$SERVIDOR" ] \
            && echo "Caiu na instância: \$SERVIDOR" \
            || echo "Resposta recebida, mas não foi possível identificar a instância"
    fi

    echo "----------------------------------------"
    sleep \$INTERVALO
done
EOF
    chmod +x "$TESTE_LB_SCRIPT"
}

# -----------------------------------------------------------------------------
# Limpeza — recursos dentro da VPC
# -----------------------------------------------------------------------------
deletar_instancias() {
    log "Encerrando instâncias..."
    local ids
    ids=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$VPC_ID" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null || true)
    if [[ -z "$ids" ]]; then
        warn "Nenhuma instância encontrada."
        return
    fi
    safe_delete aws ec2 terminate-instances --instance-ids $ids
    safe_delete aws ec2 wait instance-terminated --instance-ids $ids
}

deletar_albs() {
    log "Removendo Load Balancers..."

    # 1. Deleta todos os ALBs da VPC e aguarda cada um ser removido
    local arns
    arns=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || true)

    for arn in $arns; do
        safe_delete aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
        safe_delete aws elbv2 wait load-balancers-deleted --load-balancer-arns "$arn"
    done

    # 2. Deleta todos os Target Groups da VPC
    local tg_arns
    tg_arns=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
        --output text 2>/dev/null || true)

    for arn in $tg_arns; do
        safe_delete aws elbv2 delete-target-group --target-group-arn "$arn"
    done

    # 3. Garantia extra: tenta deletar pelo nome caso ainda existam
    local old_alb
    old_alb=$(get_alb_arn "$ALB_NAME")
    if [[ -n "$old_alb" ]]; then
        safe_delete aws elbv2 delete-load-balancer --load-balancer-arn "$old_alb"
        safe_delete aws elbv2 wait load-balancers-deleted --load-balancer-arns "$old_alb"
    fi

    local old_tg
    old_tg=$(get_tg_arn "$TG_NAME")
    if [[ -n "$old_tg" ]]; then
        safe_delete aws elbv2 delete-target-group --target-group-arn "$old_tg"
    fi

    # 4. Aguarda ENIs do ALB serem liberadas antes de prosseguir
    log "Aguardando ENIs do ALB serem liberadas..."
    aws_wait 120 10 \
        aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$VPC_ID" \
                      "Name=description,Values=ELB*" \
            --query "NetworkInterfaces[].NetworkInterfaceId" \
            --output text 2>/dev/null || true
}

deletar_efs() {
    log "Removendo EFS..."
    local efs_ids
    efs_ids=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Name'&&Value=='$EFS_NAME']].FileSystemId" \
        --output text 2>/dev/null || true)

    for efs_id in $efs_ids; do
        local mt_ids
        mt_ids=$(aws efs describe-mount-targets \
            --file-system-id "$efs_id" \
            --query "MountTargets[].MountTargetId" \
            --output text 2>/dev/null || true)

        for mt in $mt_ids; do
            safe_delete aws efs delete-mount-target --mount-target-id "$mt"
        done

        # Aguarda remoção dos mount targets antes de deletar o EFS
        aws_wait 120 10 \
            aws efs describe-mount-targets \
                --file-system-id "$efs_id" \
                --query "MountTargets[].MountTargetId" \
                --output text 2>/dev/null || true

        safe_delete aws efs delete-file-system --file-system-id "$efs_id"
    done
}

deletar_nat() {
    log "Removendo NAT Gateway..."
    local nat_ids
    nat_ids=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$VPC_ID" \
        --query "NatGateways[?State!='deleted'].NatGatewayId" \
        --output text 2>/dev/null || true)

    for nat in $nat_ids; do
        local eip
        eip=$(aws ec2 describe-nat-gateways \
            --nat-gateway-ids "$nat" \
            --query "NatGateways[0].NatGatewayAddresses[0].AllocationId" \
            --output text 2>/dev/null || true)
        safe_delete aws ec2 delete-nat-gateway --nat-gateway-id "$nat"
        safe_delete aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat"
        if [[ "$eip" != "None" && -n "$eip" ]]; then
            safe_delete aws ec2 release-address --allocation-id "$eip"
        fi
    done
}

deletar_route_tables() {
    log "Removendo tabelas de rota..."
    local rts
    rts=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
        --output text 2>/dev/null || true)

    for rt in $rts; do
        local assocs
        assocs=$(aws ec2 describe-route-tables \
            --route-table-ids "$rt" \
            --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text 2>/dev/null || true)
        for assoc in $assocs; do
            safe_delete aws ec2 disassociate-route-table --association-id "$assoc"
        done
        safe_delete aws ec2 delete-route-table --route-table-id "$rt"
    done
}

deletar_igw() {
    log "Removendo Internet Gateway..."
    local igws
    igws=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query "InternetGateways[].InternetGatewayId" \
        --output text 2>/dev/null || true)
    for igw in $igws; do
        safe_delete aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID"
        safe_delete aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
    done
}

deletar_nacls() {
    log "Removendo NACLs customizadas..."
    local default_nacl
    default_nacl=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
        --query "NetworkAcls[0].NetworkAclId" \
        --output text 2>/dev/null || true)

    local custom_nacls
    custom_nacls=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" \
        --output text 2>/dev/null || true)

    for nacl in $custom_nacls; do
        local assocs
        assocs=$(aws ec2 describe-network-acls \
            --network-acl-ids "$nacl" \
            --query "NetworkAcls[].Associations[].NetworkAclAssociationId" \
            --output text 2>/dev/null || true)
        for assoc in $assocs; do
            if [[ "$default_nacl" != "None" && -n "$default_nacl" ]]; then
                safe_delete aws ec2 replace-network-acl-association \
                    --association-id "$assoc" --network-acl-id "$default_nacl"
            fi
        done
        safe_delete aws ec2 delete-network-acl --network-acl-id "$nacl"
    done
}

deletar_subnets() {
    log "Removendo subnets..."
    local subnets
    subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[].SubnetId" \
        --output text 2>/dev/null || true)
    for s in $subnets; do
        safe_delete aws ec2 delete-subnet --subnet-id "$s"
    done
}

deletar_enis() {
    log "Aguardando e removendo interfaces de rede restantes..."
    aws_wait 180 15 \
        aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "NetworkInterfaces[].NetworkInterfaceId" \
            --output text 2>/dev/null || true

    local enis
    enis=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces[].NetworkInterfaceId" \
        --output text 2>/dev/null || true)

    for eni in $enis; do
        local att
        att=$(aws ec2 describe-network-interfaces \
            --network-interface-ids "$eni" \
            --query "NetworkInterfaces[0].Attachment.AttachmentId" \
            --output text 2>/dev/null || true)
        if [[ "$att" != "None" && -n "$att" ]]; then
            safe_delete aws ec2 detach-network-interface --attachment-id "$att" --force
        fi
        safe_delete aws ec2 delete-network-interface --network-interface-id "$eni"
    done
}

deletar_security_groups() {
    log "Removendo Security Groups..."
    local sgs
    sgs=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text 2>/dev/null || true)

    # Revoga todas as regras antes de deletar (evita dependências cruzadas entre SGs)
    for sg in $sgs; do
        local ingress egress
        ingress=$(aws ec2 describe-security-groups --group-ids "$sg" \
            --query "SecurityGroups[].IpPermissions" --output json 2>/dev/null || echo "[]")
        egress=$(aws ec2 describe-security-groups --group-ids "$sg" \
            --query "SecurityGroups[].IpPermissionsEgress" --output json 2>/dev/null || echo "[]")
        if [[ "$ingress" != "[]" ]]; then
            safe_delete aws ec2 revoke-security-group-ingress \
                --group-id "$sg" --ip-permissions "$ingress"
        fi
        if [[ "$egress" != "[]" ]]; then
            safe_delete aws ec2 revoke-security-group-egress \
                --group-id "$sg" --ip-permissions "$egress"
        fi
    done

    sleep 10

    for sg in $sgs; do
        safe_delete aws ec2 delete-security-group --group-id "$sg"
    done
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
        local result
        result=$(eval "$cmd" 2>/dev/null || true)
        echo "  $label: ${result:-nenhum}"
    done
}

deletar_vpc() {
    log "Deletando VPC..."
    for tentativa in 1 2 3; do
        log "Tentativa $tentativa de limpeza final..."
        deletar_efs
        deletar_enis
        deletar_subnets
        deletar_security_groups
        sleep 30
        if aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null; then
            log "VPC deletada com sucesso!"
            return 0
        fi
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
    associar_subnet_rt "$RT_PRIVADA" "$SUBNET_PRIVADA" "$SUBNET_DB"

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

    # EFS criado antes das instâncias para que o ID esteja disponível no user data
    EFS_ID=$(criar_efs "$SG_EFS")

    log "Gerando user data do Nginx + EFS..."
    gerar_user_data "$EFS_ID" > user_data_nginx.sh

    log "Criando instâncias frontend..."
    FRONTEND_1_ID=$(criar_instancia ec2-arandu-frontend-1 frontend "$SUBNET_PUBLICA"   10.0.1.10 "$SG_FRONTEND" user_data_nginx.sh)
    FRONTEND_2_ID=$(criar_instancia ec2-arandu-frontend-2 frontend "$SUBNET_PUBLICA_2" 10.0.4.10 "$SG_FRONTEND" user_data_nginx.sh)
    aws ec2 wait instance-running --instance-ids "$FRONTEND_1_ID" "$FRONTEND_2_ID"

    APP_DNS=$(criar_alb "$SG_ALB" "$FRONTEND_1_ID" "$FRONTEND_2_ID")
    APP_URL="http://$APP_DNS"

    log "Criando instâncias backend e banco..."
    BACKEND_ID=$(criar_instancia ec2-arandu-backend backend "$SUBNET_PRIVADA" 10.0.2.10 "$SG_BACKEND")
    DB_ID=$(criar_instancia       ec2-arandu-db      db      "$SUBNET_DB"     10.0.3.10 "$SG_DB")
    aws ec2 wait instance-running --instance-ids "$BACKEND_ID" "$DB_ID"

    gerar_script_teste "$APP_URL"
    rm -f user_data_nginx.sh

    echo ""
    log "Infraestrutura criada com sucesso!"
    log "EFS ID:           $EFS_ID"
    log "URL da aplicação: $APP_URL"
    log "Teste do balanceador: ./$TESTE_LB_SCRIPT"
    warn "Se abrir antes dos targets ficarem saudáveis, aguarde alguns instantes e atualize a página."
}

# -----------------------------------------------------------------------------
# Fluxo principal — Deleção
# -----------------------------------------------------------------------------
deletar_infraestrutura() {
    deletar_instancias
    deletar_albs      # já aguarda as ENIs do ALB sumirem internamente
    deletar_efs
    deletar_nat
    deletar_route_tables
    deletar_igw
    deletar_nacls
    deletar_subnets
    deletar_enis
    deletar_security_groups

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
    read -r opcao
    [[ "$opcao" == "2" ]] && deletar_infraestrutura
fi
