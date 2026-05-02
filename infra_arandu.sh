#!/bin/bash

export AWS_PAGER=""
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"
set -e

REGIAO="us-east-1"
TESTE_LB_SCRIPT="testar_loadbalancer.sh"
ALB_NAME="alb-arandu-frontend"
TG_NAME="tg-arandu-frontend"
KEY_NAME="arandu-key"

# Remove ALB e TG antigos com o mesmo nome
limpar_alb_tg_por_nome() {
    ALB_ARN_EXISTENTE=$(aws elbv2 describe-load-balancers     --names "$ALB_NAME"     --query "LoadBalancers[0].LoadBalancerArn"     --output text 2>/dev/null || true)

    if [[ "$ALB_ARN_EXISTENTE" != "None" && -n "$ALB_ARN_EXISTENTE" ]]; then
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN_EXISTENTE" 2>/dev/null || true
        aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN_EXISTENTE" 2>/dev/null || true
    fi

    TG_ARN_EXISTENTE=$(aws elbv2 describe-target-groups     --names "$TG_NAME"     --query "TargetGroups[0].TargetGroupArn"     --output text 2>/dev/null || true)

    if [[ "$TG_ARN_EXISTENTE" != "None" && -n "$TG_ARN_EXISTENTE" ]]; then
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN_EXISTENTE" 2>/dev/null || true
    fi
}


# Mostra recursos que impedem remover a VPC
mostrar_dependencias_vpc() {
    echo "Subnets restantes:"
    aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[].SubnetId" \
    --output text 2>/dev/null || true

    echo "Interfaces de rede restantes:"
    aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Descricao:Description}" \
    --output table 2>/dev/null || true

    echo "Security Groups restantes:"
    aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].{Id:GroupId,Nome:GroupName}" \
    --output table 2>/dev/null || true

    echo "Route Tables restantes:"
    aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "RouteTables[].RouteTableId" \
    --output text 2>/dev/null || true

    echo "Internet Gateways restantes:"
    aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[].InternetGatewayId" \
    --output text 2>/dev/null || true
}

# Repete limpeza de recursos presos
limpar_dependencias_restantes() {
    ALB_ARNS=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
    --output text 2>/dev/null || true)

    for alb in $ALB_ARNS; do
        aws elbv2 delete-load-balancer --load-balancer-arn $alb 2>/dev/null || true
        aws elbv2 wait load-balancers-deleted --load-balancer-arns $alb 2>/dev/null || true
    done

    TG_ARNS=$(aws elbv2 describe-target-groups \
    --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
    --output text 2>/dev/null || true)

    for tg in $TG_ARNS; do
        aws elbv2 delete-target-group --target-group-arn $tg 2>/dev/null || true
    done

    NAT_IDS=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC_ID" \
    --query "NatGateways[?State!='deleted'].NatGatewayId" \
    --output text 2>/dev/null || true)

    for nat in $NAT_IDS; do
        EIP_ALLOC=$(aws ec2 describe-nat-gateways \
        --nat-gateway-ids $nat \
        --query "NatGateways[0].NatGatewayAddresses[0].AllocationId" \
        --output text 2>/dev/null || true)

        aws ec2 delete-nat-gateway --nat-gateway-id $nat 2>/dev/null || true
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids $nat 2>/dev/null || true

        if [[ "$EIP_ALLOC" != "None" && -n "$EIP_ALLOC" ]]; then
            aws ec2 release-address --allocation-id $EIP_ALLOC 2>/dev/null || true
        fi
    done

    ROUTE_TABLES=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
    --output text 2>/dev/null || true)

    for rt in $ROUTE_TABLES; do
        ASSOCIATIONS=$(aws ec2 describe-route-tables \
        --route-table-ids $rt \
        --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
        --output text 2>/dev/null || true)

        for assoc in $ASSOCIATIONS; do
            aws ec2 disassociate-route-table --association-id $assoc 2>/dev/null || true
        done

        aws ec2 delete-route-table --route-table-id $rt 2>/dev/null || true
    done

    IGW=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[].InternetGatewayId" \
    --output text 2>/dev/null || true)

    for igw in $IGW; do
        aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null || true
    done

    DEFAULT_NACL=$(aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
    --query "NetworkAcls[0].NetworkAclId" \
    --output text 2>/dev/null || true)

    CUSTOM_NACLS=$(aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" \
    --output text 2>/dev/null || true)

    for nacl in $CUSTOM_NACLS; do
        NACL_ASSOCS=$(aws ec2 describe-network-acls \
        --network-acl-ids $nacl \
        --query "NetworkAcls[].Associations[].NetworkAclAssociationId" \
        --output text 2>/dev/null || true)

        for assoc in $NACL_ASSOCS; do
            if [[ "$DEFAULT_NACL" != "None" && -n "$DEFAULT_NACL" ]]; then
                aws ec2 replace-network-acl-association --association-id $assoc --network-acl-id $DEFAULT_NACL 2>/dev/null || true
            fi
        done

        aws ec2 delete-network-acl --network-acl-id $nacl 2>/dev/null || true
    done

    SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[].SubnetId" \
    --output text 2>/dev/null || true)

    for s in $SUBNETS; do
        aws ec2 delete-subnet --subnet-id $s 2>/dev/null || true
    done

    ENIS=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text 2>/dev/null || true)

    for eni in $ENIS; do
        ATTACHMENT_ID=$(aws ec2 describe-network-interfaces \
        --network-interface-ids $eni \
        --query "NetworkInterfaces[0].Attachment.AttachmentId" \
        --output text 2>/dev/null || true)

        if [[ "$ATTACHMENT_ID" != "None" && -n "$ATTACHMENT_ID" ]]; then
            aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force 2>/dev/null || true
        fi

        aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null || true
    done

    SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text 2>/dev/null || true)

    for sg in $SG; do
        INGRESS_RULES=$(aws ec2 describe-security-groups \
        --group-ids $sg \
        --query "SecurityGroups[].IpPermissions" \
        --output json 2>/dev/null || echo "[]")

        if [ "$INGRESS_RULES" != "[]" ]; then
            aws ec2 revoke-security-group-ingress --group-id $sg --ip-permissions "$INGRESS_RULES" 2>/dev/null || true
        fi

        EGRESS_RULES=$(aws ec2 describe-security-groups \
        --group-ids $sg \
        --query "SecurityGroups[].IpPermissionsEgress" \
        --output json 2>/dev/null || echo "[]")

        if [ "$EGRESS_RULES" != "[]" ]; then
            aws ec2 revoke-security-group-egress --group-id $sg --ip-permissions "$EGRESS_RULES" 2>/dev/null || true
        fi
    done

    for sg in $SG; do
        aws ec2 delete-security-group --group-id $sg 2>/dev/null || true
    done
}

clear

echo -e "\n\n\n"
echo -e "\e[32m"
echo -e "\e[34mJá digitou suas credenciais de acesso nas últimas 4 horas? (s/n)\e[0m"
read resposta

# Configura credenciais temporárias
if [[ "$resposta" != "s" && "$resposta" != "S" ]]; then
    echo -e "\e[32mInforme as credenciais temporárias da AWS.\e[0m"

    echo "Digite o AWS Access Key ID:"
    read accessKey

    echo "Digite o AWS Secret Access Key:"
    read secretKey

    echo "Digite o Session Token:"
    read sessionToken

    aws configure set aws_access_key_id "$accessKey"
    aws configure set aws_secret_access_key "$secretKey"
    aws configure set aws_session_token "$sessionToken"
    aws configure set default.region "$REGIAO"

    echo -e "\e[32mCredenciais cadastradas. Continuando...\e[0m"
fi

# Busca a VPC principal
VPC_ID=$(aws ec2 describe-vpcs \
--filters "Name=tag:Name,Values=vpc-arandu" \
--query "Vpcs[0].VpcId" \
--output text)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then

    echo -e "\n\e[31m(!) - VPC não existe\e[0m"
    echo -e "\e[32m(!) - Criando VPC...\e[0m\n"

    # Cria a VPC
    VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=vpc-arandu}]' \
    --query 'Vpc.VpcId' \
    --output text)

    aws ec2 wait vpc-available --vpc-ids $VPC_ID

    # Cria as subnets
    echo -e "\e[32m(!) - Criando subnets...\e[0m\n"

    SUBNET_PUBLICA=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-frontend-publica-arandu}]' \
    --query 'Subnet.SubnetId' \
    --output text)

    aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLICA --map-public-ip-on-launch

    SUBNET_PUBLICA_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.4.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-frontend-publica-arandu-2}]' \
    --query 'Subnet.SubnetId' \
    --output text)

    aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLICA_2 --map-public-ip-on-launch

    SUBNET_PRIVADA=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-backend-privada-arandu}]' \
    --query 'Subnet.SubnetId' \
    --output text)

    SUBNET_DB=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.3.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-privada-db-arandu}]' \
    --query 'Subnet.SubnetId' \
    --output text)

    # Cria o Internet Gateway
    echo -e "\e[32m(!) - Criando Internet Gateway...\e[0m\n"

    INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=internet-gateway-arandu}]' \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

    aws ec2 attach-internet-gateway \
    --internet-gateway-id $INTERNET_GATEWAY_ID \
    --vpc-id $VPC_ID

    # Cria a rota pública
    echo -e "\e[32m(!) - Criando rota pública...\e[0m\n"

    ROTA_PUBLICA_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rota-publica-arandu}]' \
    --query 'RouteTable.RouteTableId' \
    --output text)

    aws ec2 create-route \
    --route-table-id $ROTA_PUBLICA_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $INTERNET_GATEWAY_ID

    aws ec2 associate-route-table --route-table-id $ROTA_PUBLICA_ID --subnet-id $SUBNET_PUBLICA
    aws ec2 associate-route-table --route-table-id $ROTA_PUBLICA_ID --subnet-id $SUBNET_PUBLICA_2

    # Cria o NAT Gateway
    echo -e "\e[32m(!) - Criando NAT Gateway...\e[0m\n"

    IP_ELASTICO_NAT_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --query 'AllocationId' \
    --output text)

    NAT_ID=$(aws ec2 create-nat-gateway \
    --subnet-id $SUBNET_PUBLICA \
    --allocation-id $IP_ELASTICO_NAT_ID \
    --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=nat-arandu}]' \
    --query 'NatGateway.NatGatewayId' \
    --output text)

    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

    # Cria a rota privada
    echo -e "\e[32m(!) - Criando rota privada...\e[0m\n"

    ROTA_PRIVADA_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rota-privada-arandu}]' \
    --query 'RouteTable.RouteTableId' \
    --output text)

    aws ec2 create-route \
    --route-table-id $ROTA_PRIVADA_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_ID

    aws ec2 associate-route-table --route-table-id $ROTA_PRIVADA_ID --subnet-id $SUBNET_PRIVADA
    aws ec2 associate-route-table --route-table-id $ROTA_PRIVADA_ID --subnet-id $SUBNET_DB

    # Cria a NACL pública
    echo -e "\e[32m(!) - Criando NACL pública...\e[0m\n"

    NACL_ID=$(aws ec2 create-network-acl \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=nacl-publica-arandu}]' \
    --query 'NetworkAcl.NetworkAclId' \
    --output text)

    aws ec2 create-network-acl-entry \
    --network-acl-id $NACL_ID \
    --ingress \
    --rule-number 100 \
    --protocol tcp \
    --port-range From=80,To=80 \
    --cidr-block 0.0.0.0/0 \
    --rule-action allow

    aws ec2 create-network-acl-entry \
    --network-acl-id $NACL_ID \
    --ingress \
    --rule-number 110 \
    --protocol tcp \
    --port-range From=22,To=22 \
    --cidr-block 0.0.0.0/0 \
    --rule-action allow

    aws ec2 create-network-acl-entry \
    --network-acl-id $NACL_ID \
    --ingress \
    --rule-number 120 \
    --protocol tcp \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0 \
    --rule-action allow

    aws ec2 create-network-acl-entry \
    --network-acl-id $NACL_ID \
    --egress \
    --rule-number 100 \
    --protocol -1 \
    --cidr-block 0.0.0.0/0 \
    --rule-action allow

    ASSOC_ID_PUBLICA=$(aws ec2 describe-network-acls \
    --filters "Name=association.subnet-id,Values=$SUBNET_PUBLICA" \
    --query "NetworkAcls[].Associations[?SubnetId=='$SUBNET_PUBLICA'].NetworkAclAssociationId" \
    --output text)

    ASSOC_ID_PUBLICA_2=$(aws ec2 describe-network-acls \
    --filters "Name=association.subnet-id,Values=$SUBNET_PUBLICA_2" \
    --query "NetworkAcls[].Associations[?SubnetId=='$SUBNET_PUBLICA_2'].NetworkAclAssociationId" \
    --output text)

    aws ec2 replace-network-acl-association --association-id $ASSOC_ID_PUBLICA --network-acl-id $NACL_ID
    aws ec2 replace-network-acl-association --association-id $ASSOC_ID_PUBLICA_2 --network-acl-id $NACL_ID

    # Cria os Security Groups
    echo -e "\e[32m(!) - Criando Security Groups...\e[0m\n"

    SG_FRONTEND=$(aws ec2 create-security-group \
    --group-name arandu-sg-frontend \
    --description "SG Frontend Arandu" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

    aws ec2 create-tags --resources $SG_FRONTEND --tags Key=Name,Value=arandu-sg-frontend
    aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND --protocol tcp --port 22 --cidr 0.0.0.0/0

    SG_ALB=$(aws ec2 create-security-group \
    --group-name arandu-sg-alb \
    --description "SG Load Balancer Arandu" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

    aws ec2 create-tags --resources $SG_ALB --tags Key=Name,Value=arandu-sg-alb
    aws ec2 authorize-security-group-ingress --group-id $SG_ALB --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND --protocol tcp --port 80 --source-group $SG_ALB

    SG_BACKEND=$(aws ec2 create-security-group \
    --group-name arandu-sg-backend \
    --description "SG Backend Arandu" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

    aws ec2 create-tags --resources $SG_BACKEND --tags Key=Name,Value=arandu-sg-backend
    aws ec2 authorize-security-group-ingress --group-id $SG_BACKEND --protocol tcp --port 8080 --source-group $SG_FRONTEND
    aws ec2 authorize-security-group-ingress --group-id $SG_BACKEND --protocol tcp --port 22 --source-group $SG_FRONTEND

    SG_DB=$(aws ec2 create-security-group \
    --group-name arandu-sg-db \
    --description "SG Database Arandu" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

    aws ec2 create-tags --resources $SG_DB --tags Key=Name,Value=arandu-sg-db
    aws ec2 authorize-security-group-ingress --group-id $SG_DB --protocol tcp --port 3306 --source-group $SG_BACKEND
    aws ec2 authorize-security-group-ingress --group-id $SG_DB --protocol tcp --port 22 --source-group $SG_BACKEND

    # Busca a AMI Ubuntu
    echo -e "\e[32m(!) - Buscando AMI Ubuntu...\e[0m\n"

    IMAGEM_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
    --output text)

    # Cria a chave SSH
    echo -e "\e[32m(!) - Criando chave SSH...\e[0m\n"

    aws ec2 delete-key-pair --key-name $KEY_NAME 2>/dev/null || true
    rm -f arandu-key.pem

    aws ec2 create-key-pair \
    --key-name $KEY_NAME \
    --key-type rsa \
    --query 'KeyMaterial' \
    --output text > arandu-key.pem

    chmod 400 arandu-key.pem

    # Cria o User Data do Nginx
    cat <<EOF_USER_DATA > user_data_nginx.sh
#!/bin/bash
apt-get update -y
apt-get install nginx -y

HOSTNAME_ATUAL=\$(hostname)

cat <<HTML > /var/www/html/index.html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Arandu Frontend</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f4f7fb;
            color: #1f2937;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }

        .card {
            background: white;
            padding: 32px;
            border-radius: 12px;
            box-shadow: 0 8px 24px rgba(0,0,0,0.12);
            text-align: center;
        }

        h1 {
            margin-bottom: 8px;
            color: #2563eb;
        }

        p {
            margin: 6px 0;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>Frontend Arandu</h1>
        <p>Instância EC2 com Nginx funcionando.</p>
        <p>Balanceamento de carga ativo.</p>
        <p><strong>Servidor:</strong> \$HOSTNAME_ATUAL</p>
    </div>
</body>
</html>
HTML

systemctl start nginx
systemctl enable nginx
EOF_USER_DATA

    # Cria as instâncias frontend
    echo -e "\e[32m(!) - Criando frontends...\e[0m\n"

    FRONTEND_1_ID=$(aws ec2 run-instances \
    --image-id $IMAGEM_ID \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_PUBLICA \
    --private-ip-address 10.0.1.10 \
    --security-group-ids $SG_FRONTEND \
    --associate-public-ip-address \
    --user-data file://user_data_nginx.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-frontend-1},{Key=Role,Value=frontend}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

    FRONTEND_2_ID=$(aws ec2 run-instances \
    --image-id $IMAGEM_ID \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_PUBLICA_2 \
    --private-ip-address 10.0.4.10 \
    --security-group-ids $SG_FRONTEND \
    --associate-public-ip-address \
    --user-data file://user_data_nginx.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-frontend-2},{Key=Role,Value=frontend}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

    aws ec2 wait instance-running --instance-ids $FRONTEND_1_ID $FRONTEND_2_ID

    # Limpa ALB/TG antigos
    echo -e "\e[32m(!) - Limpando Load Balancer antigo, se existir...\e[0m\n"
    limpar_alb_tg_por_nome

    # Cria o Load Balancer
    echo -e "\e[32m(!) - Criando Load Balancer...\e[0m\n"

    ALB_ARN=$(aws elbv2 create-load-balancer \
    --name $ALB_NAME \
    --subnets $SUBNET_PUBLICA $SUBNET_PUBLICA_2 \
    --security-groups $SG_ALB \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --tags Key=Name,Value=$ALB_NAME \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name $TG_NAME \
    --protocol HTTP \
    --port 80 \
    --vpc-id $VPC_ID \
    --target-type instance \
    --health-check-protocol HTTP \
    --health-check-path "/" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

    aws elbv2 register-targets \
    --target-group-arn $TARGET_GROUP_ARN \
    --targets Id=$FRONTEND_1_ID,Port=80 Id=$FRONTEND_2_ID,Port=80

    aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

    ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

    APP_URL="http://$ALB_DNS"

    echo -e "\e[32m(!) - Load Balancer criado: $APP_URL\e[0m\n"

    # Cria script de teste do ALB
    cat <<EOF_TESTE_LB > "$TESTE_LB_SCRIPT"
#!/bin/bash

URL="$APP_URL"
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

        if [ -n "\$SERVIDOR" ]; then
            echo "Caiu na instância: \$SERVIDOR"
        else
            echo "Resposta recebida, mas não foi possível identificar a instância"
        fi
    fi

    echo "----------------------------------------"
    sleep \$INTERVALO
done
EOF_TESTE_LB

    chmod +x "$TESTE_LB_SCRIPT"

    # Aguarda health check
    aws elbv2 wait target-in-service \
    --target-group-arn $TARGET_GROUP_ARN \
    --targets Id=$FRONTEND_1_ID,Port=80 Id=$FRONTEND_2_ID,Port=80 2>/dev/null || true

    # Cria backend e banco
    echo -e "\e[32m(!) - Criando backend e banco...\e[0m\n"

    BACKEND_ID=$(aws ec2 run-instances \
    --image-id $IMAGEM_ID \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_PRIVADA \
    --private-ip-address 10.0.2.10 \
    --security-group-ids $SG_BACKEND \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-backend},{Key=Role,Value=backend}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

    DB_ID=$(aws ec2 run-instances \
    --image-id $IMAGEM_ID \
    --instance-type t2.micro \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_DB \
    --private-ip-address 10.0.3.10 \
    --security-group-ids $SG_DB \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-db},{Key=Role,Value=db}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

    aws ec2 wait instance-running --instance-ids $BACKEND_ID $DB_ID

    rm -f user_data_nginx.sh

    echo -e "\e[32mInfraestrutura criada com sucesso!\e[0m"
    echo -e "\e[32mURL da aplicação: $APP_URL\e[0m"
    echo -e "\e[32mTeste do balanceador: ./$TESTE_LB_SCRIPT\e[0m"
    echo -e "\e[33mSe abrir antes dos targets ficarem saudáveis, aguarde alguns instantes e atualize a página.\e[0m"

else
    echo -e "\e[31mVPC já existe: $VPC_ID\e[0m"
    echo "1 - Manter infraestrutura"
    echo "2 - Deletar TUDO da VPC"
    read opcao

    if [[ "$opcao" == "2" ]]; then

        # Encerra instâncias
        echo -e "\e[32m(!) - Encerrando instâncias...\e[0m\n"

        INSTANCIAS=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)

        if [ -n "$INSTANCIAS" ]; then
            aws ec2 terminate-instances --instance-ids $INSTANCIAS 2>/dev/null || true
            aws ec2 wait instance-terminated --instance-ids $INSTANCIAS 2>/dev/null || true
        fi

        # Remove ALB e Target Groups
        echo -e "\e[32m(!) - Removendo Load Balancer...\e[0m\n"

        ALB_ARNS=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || true)

        for alb in $ALB_ARNS; do
            aws elbv2 delete-load-balancer --load-balancer-arn $alb 2>/dev/null || true
            aws elbv2 wait load-balancers-deleted --load-balancer-arns $alb 2>/dev/null || true
        done

        TG_ARNS=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
        --output text 2>/dev/null || true)

        for tg in $TG_ARNS; do
            aws elbv2 delete-target-group --target-group-arn $tg 2>/dev/null || true
        done

        limpar_alb_tg_por_nome

        # Remove NAT e Elastic IP
        echo -e "\e[32m(!) - Removendo NAT Gateway...\e[0m\n"

        NAT_IDS=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$VPC_ID" \
        --query "NatGateways[?State!='deleted'].NatGatewayId" \
        --output text 2>/dev/null || true)

        for nat in $NAT_IDS; do
            EIP_ALLOC=$(aws ec2 describe-nat-gateways \
            --nat-gateway-ids $nat \
            --query "NatGateways[0].NatGatewayAddresses[0].AllocationId" \
            --output text 2>/dev/null || true)

            aws ec2 delete-nat-gateway --nat-gateway-id $nat 2>/dev/null || true
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids $nat 2>/dev/null || true

            if [[ "$EIP_ALLOC" != "None" && -n "$EIP_ALLOC" ]]; then
                aws ec2 release-address --allocation-id $EIP_ALLOC 2>/dev/null || true
            fi
        done

        # Remove rotas customizadas
        echo -e "\e[32m(!) - Removendo tabelas de rota...\e[0m\n"

        ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
        --output text 2>/dev/null || true)

        for rt in $ROUTE_TABLES; do
            ASSOCIATIONS=$(aws ec2 describe-route-tables \
            --route-table-ids $rt \
            --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text 2>/dev/null || true)

            for assoc in $ASSOCIATIONS; do
                aws ec2 disassociate-route-table --association-id $assoc 2>/dev/null || true
            done

            aws ec2 delete-route-table --route-table-id $rt 2>/dev/null || true
        done

        # Remove Internet Gateway
        echo -e "\e[32m(!) - Removendo Internet Gateway...\e[0m\n"

        IGW=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query "InternetGateways[].InternetGatewayId" \
        --output text 2>/dev/null || true)

        if [ -n "$IGW" ]; then
            aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID 2>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id $IGW 2>/dev/null || true
        fi

        # Reassocia NACL padrão
        echo -e "\e[32m(!) - Removendo NACLs customizadas...\e[0m\n"

        DEFAULT_NACL=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
        --query "NetworkAcls[0].NetworkAclId" \
        --output text 2>/dev/null || true)

        CUSTOM_NACLS=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" \
        --output text 2>/dev/null || true)

        for nacl in $CUSTOM_NACLS; do
            NACL_ASSOCS=$(aws ec2 describe-network-acls \
            --network-acl-ids $nacl \
            --query "NetworkAcls[].Associations[].NetworkAclAssociationId" \
            --output text 2>/dev/null || true)

            for assoc in $NACL_ASSOCS; do
                if [[ "$DEFAULT_NACL" != "None" && -n "$DEFAULT_NACL" ]]; then
                    aws ec2 replace-network-acl-association --association-id $assoc --network-acl-id $DEFAULT_NACL 2>/dev/null || true
                fi
            done

            aws ec2 delete-network-acl --network-acl-id $nacl 2>/dev/null || true
        done

        # Remove subnets
        echo -e "\e[32m(!) - Removendo subnets...\e[0m\n"

        SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[].SubnetId" \
        --output text 2>/dev/null || true)

        for s in $SUBNETS; do
            aws ec2 delete-subnet --subnet-id $s 2>/dev/null || true
        done

        # Remove ENIs restantes
        echo -e "\e[32m(!) - Removendo interfaces de rede...\e[0m\n"

        sleep 60

        ENIS=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces[].NetworkInterfaceId" \
        --output text 2>/dev/null || true)

        for eni in $ENIS; do
            aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null || true
        done

        # Remove Security Groups
        echo -e "\e[32m(!) - Removendo Security Groups...\e[0m\n"

        SG=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text 2>/dev/null || true)

        for sg in $SG; do
            INGRESS_RULES=$(aws ec2 describe-security-groups \
            --group-ids $sg \
            --query "SecurityGroups[].IpPermissions" \
            --output json 2>/dev/null || echo "[]")

            if [ "$INGRESS_RULES" != "[]" ]; then
                aws ec2 revoke-security-group-ingress --group-id $sg --ip-permissions "$INGRESS_RULES" 2>/dev/null || true
            fi

            EGRESS_RULES=$(aws ec2 describe-security-groups \
            --group-ids $sg \
            --query "SecurityGroups[].IpPermissionsEgress" \
            --output json 2>/dev/null || echo "[]")

            if [ "$EGRESS_RULES" != "[]" ]; then
                aws ec2 revoke-security-group-egress --group-id $sg --ip-permissions "$EGRESS_RULES" 2>/dev/null || true
            fi
        done

        sleep 20

        for sg in $SG; do
            aws ec2 delete-security-group --group-id $sg 2>/dev/null || true
        done

        # Remove arquivos locais
        echo -e "\e[32m(!) - Removendo arquivos locais...\e[0m\n"

        aws ec2 delete-key-pair --key-name $KEY_NAME 2>/dev/null || true
        rm -f arandu-key.pem
        rm -f "$TESTE_LB_SCRIPT"

        # Remove VPC
        echo -e "\e[32m(!) - Verificando dependências finais...\e[0m\n"
        mostrar_dependencias_vpc

        VPC_DELETADA="n"

        for tentativa in 1 2 3; do
            echo -e "\e[32m(!) - Tentativa $tentativa de limpeza final...\e[0m\n"
            limpar_dependencias_restantes
            sleep 60

            echo -e "\e[32m(!) - Deletando VPC...\e[0m\n"
            if aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null; then
                VPC_DELETADA="s"
                break
            fi
        done

        if [[ "$VPC_DELETADA" == "s" ]]; then
            echo -e "\e[32mInfraestrutura removida com sucesso!\e[0m"
        else
            echo -e "\e[31m(!) - A VPC ainda não foi deletada. Dependências restantes:\e[0m"
            mostrar_dependencias_vpc
            echo -e "\e[33mAguarde alguns minutos e rode a opção 2 novamente, pois ENIs de ALB/NAT podem demorar para sumir.\e[0m"
        fi
    fi
fi
