#!/bin/bash

# "!/bin/bash" indica qual interpretador deve ser usado para executar o script, nesse caso o bash
export AWS_PAGER=""
set -e # Faz com que o script pare a execução caso ocorra algum erro em algum comando evitando criar uma infraestrutura incompleta ou com erros

clear # Limpa o terminal


echo -e "\n\n\n" # echo é o comando mais básico, ele volta uma mensagem no terminal
# -e na frente permite que ele interprete "\" que nos casos abaixo é utilizado para dar quebra de linha e para colorir o texto com o \n e o \e[x

echo -e "\e[32m"

# << = here document, serve para passar diversas linhas de texto em um comando, nesse caso o cat que concatena as linhas, deixando elas  como se fosse um único arquivo
cat <<'ARTE_ASCII' # '' define um marcador para o texto, nesse caso ARTE_ASCII, que pode ser qualquer coisa, mas tem que ser a mesma coisa no início e no final
       d8888 8888888b.         d8888 888b    888 8888888b.  888     888      8888888b. 8888888 .d8888b.  8888888 88888888888     d8888 888      
      d88888 888   Y88b       d88888 8888b   888 888  "Y88b 888     888      888  "Y88b  888  d88P  Y88b   888       888        d88888 888      
     d88P888 888    888      d88P888 88888b  888 888    888 888     888      888    888  888  888    888   888       888       d88P888 888      
    d88P 888 888   d88P     d88P 888 888Y88b 888 888    888 888     888      888    888  888  888          888       888      d88P 888 888      
   d88P  888 8888888P"     d88P  888 888 Y88b888 888    888 888     888      888    888  888  888  88888   888       888     d88P  888 888      
  d88P   888 888 T88b     d88P   888 888  Y88888 888    888 888     888      888    888  888  888    888   888       888    d88P   888 888      
 d8888888888 888  T88b   d8888888888 888   Y8888 888  .d88P Y88b. .d88P      888  .d88P  888  Y88b  d88P   888       888   d8888888888 888      
d88P     888 888   T88b d88P     888 888    Y888 8888888P"   "Y88888P"       8888888P" 8888888 "Y8888P88 8888888     888  d88P     888 88888888                                                                                                                                              
ARTE_ASCII
echo -e "\e[0m"
echo -e "\n\n\n"

cat <<'ARTE_ASCII'                                                                                                                                                                                                               
   __________  __________  _______   _______________    _________
  / ____/ __ \/ ____/ __ \/ ____/ | / / ____/  _/   |  /  _/ ___/
 / /   / /_/ / __/ / / / / __/ /  |/ / /    / // /| |  / / \__ \ 
/ /___/ _, _/ /___/ /_/ / /___/ /|  / /____/ // ___ |_/ / ___/ / 
\____/_/ |_/_____/_____/_____/_/ |_/\____/___/_/  |_/___//____/                                                                                                                                                                                                                                                                                   
ARTE_ASCII
echo "========================================================================================================================================"

# Essa parte é basicamente um AWS configure


echo -e "\e[34mJá digitou suas credenciais de acesso nas últimas 4 horas (não esqueça de verificar o tempo restante na aws)? (s/n)\e[0m"
read resposta # read lê a resposta do usuário e armazena na variável 

# Verifica a letra informa pelo usuário, se for diferente de "s", ele pede para o usuário informar as credenciais de acesso
if [[ "$resposta" != "s" && "$resposta" != "S" ]]; then
    echo -e "\e[32mPara descobrir suas credenciais de acesso, acesse o console da AWS na web e execute o comando 'cat .aws/credentials'\e[0m"

    # Pega a Acess Key
    echo "Digite o AWS Access Key ID:"
    read accessKey

    # Pega a Secret Key
    echo "Digite o AWS Secret Access Key:"
    read secretKey

    # Pega o Session Token
    echo "Digite o token de sessão temporário (Session Token): "
    read sessionToken

    # (i) - Comandos aws começam sempre com "aws", depois vem o serviço, nesse caso "configure", e depois a ação, nesse caso "set", que é para configurar as credenciais de acesso, e depois vem o nome da credencial, que pode ser "aws_access_key_id", "aws_secret_access_key" ou "aws_session_token", e por último vem o valor da credencial, que é a variável que armazena a resposta do usuário

    # Configura a Acess Key na AWS
    aws configure set aws_access_key_id "$accessKey"
    # Configura a Secret Key na AWS
    aws configure set aws_secret_access_key "$secretKey"
    # Configura o Session Token na AWS
    aws configure set aws_session_token "$sessionToken"
    # Deixa a região padrão como us-east-1
    aws configure set default.region "us-east-1"

    echo -e "\e[32mCredenciais cadastradas com sucesso! Execute o programa novamente e responda com a letra 's'.\e[0m"
    exit 
fi

# aws (início do comando), "ec2" (serviço que vai ser usado), describe-vpcs (ação que vai ser executada) 
# --filters (opção para filtrar os resultados, nesse caso o filtro é "Name=tag:Name,Values=vpc-arandu", que significa que ele vai procurar por VPCs que tenham a tag "Name" com o valor "vpc-arandu")
# --query (opção para formatar a saída do comando, nesse caso ele vai pegar o primeiro VPC encontrado e retornar apenas o ID do VPC) 
# --output (opção para definir o formato da saída, nesse caso "text" para retornar apenas o texto do ID do VPC)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-arandu" --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then # Verifica se a variável VPC_ID é igual a "None" ou está vazia atráves do -z, o que significa que o VPC não existe, e se for o caso, ele cria o VPC
    
cat <<'ARTE_ASCII'                                                                                                                                                                                                                                                                                 
 _    ______  ______
| |  / / __ \/ ____/
| | / / /_/ / /     
| |/ / ____/ /___   
|___/_/    \____/                                                                                                                                                                                                                                                                                                                                                                                      
ARTE_ASCII
echo "========================================================================================================================================"

    echo -e "\n\e[31m(!) - VPC não existe\e[0m"
    echo -e "\e[32m(!) - Criando VPC...\e[0m\n"

    # aws (início do comando), "ec2" (serviço que vai ser usado), create-vpc (ação que vai ser executada) e especificações com --
    # --cidr-block (opção para definir o bloco CIDR do VPC)
    # --tag-specifications (opção para definir as tags do VPC, nesse caso o nome do VPC é "vpc-arandu")
    VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=vpc-arandu}]' --query 'Vpc.VpcId' --output text)

    # Espera o VPC ficar disponível, para garantir que ele esteja pronto para ser usado antes de criar as subredes e os outros recursos que dependem do VPC
    aws ec2 wait vpc-available --vpc-ids $VPC_ID

cat <<'ARTE_ASCII'                                                                                                                                                                                                                                                                                                                                                                                      
   _____ __  ______  ____  __________  ___________
  / ___// / / / __ )/ __ \/ ____/ __ \/ ____/ ___/
  \__ \/ / / / __  / /_/ / __/ / / / / __/  \__ \ 
 ___/ / /_/ / /_/ / _, _/ /___/ /_/ / /___ ___/ / 
/____/\____/_____/_/ |_/_____/_____/_____//____/                                                                                                                                                                                                                                                                                                                                                                                                                                                       
ARTE_ASCII
echo "========================================================================================================================================"

    echo -e "\e[32m(!) - Criando subrede publica Frontend...\e[0m\n"
    # Cria subred do frontend dentro do VPC criado
    SUBNET_PUBLICA=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-frontend-publica-arandu}]' --query 'Subnet.SubnetId' --output text)
    aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLICA --map-public-ip-on-launch

    echo -e "\e[32m(!) - Criando subrede privada Backend...\e[0m\n"
    # Cria subred do backend dentro do VPC criado
    SUBNET_PRIVADA=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-backend-privada-arandu}]' --query 'Subnet.SubnetId' --output text)

    echo -e "\e[32m(!) - Criando subrede privada DB...\e[0m\n"
    SUBNET_DB=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-privada-db-arandu}]' --query 'Subnet.SubnetId' --output text)

    # Ambas subredes estão com bloco CIDR /24, com 256 endereços IP disponíveis

cat <<'ARTE_ASCII'                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        
    _____   __________________  _   ______________   _________  _____________       _______  _______
   /  _/ | / /_  __/ ____/ __ \/ | / / ____/_  __/  / ____/   |/_  __/ ____/ |     / /   \ \/ / ___/
   / //  |/ / / / / __/ / /_/ /  |/ / __/   / /    / / __/ /| | / / / __/  | | /| / / /| |\  /\__ \ 
 _/ // /|  / / / / /___/ _, _/ /|  / /___  / /    / /_/ / ___ |/ / / /___  | |/ |/ / ___ |/ /___/ / 
/___/_/ |_/ /_/ /_____/_/ |_/_/ |_/_____/ /_/     \____/_/  |_/_/ /_____/  |__/|__/_/  |_/_//____/                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                
ARTE_ASCII
echo "========================================================================================================================================"

    # Criando um Internet Gateway, que é um componente que permite a comunicação entre o VPC e a internet, e associando ele ao VPC criado
    echo -e "\e[32m(!) - Criando Internet Gateway...\e[0m\n"
    INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=internet-gateway-arandu}]' --query 'InternetGateway.InternetGatewayId' --output text)

    # Associando o Internet Gateway ao VPC criado
    echo -e "\e[32m(!) - Associando Internet Gateway ao VPC...\e[0m\n"
    aws ec2 attach-internet-gateway --internet-gateway-id $INTERNET_GATEWAY_ID --vpc-id $VPC_ID

cat <<'ARTE_ASCII'                                                                                                                       
    ____  ____  __  ______________   _________    ____  __    ______   ____    __  ____  __    _____________ 
   / __ \/ __ \/ / / /_  __/ ____/  /_  __/   |  / __ )/ /   / ____/  / __ \__/_/_/ __ )/ /   /  _/ ____/   |
  / /_/ / / / / / / / / / / __/      / / / /| | / __  / /   / __/    / /_/ / / / / __  / /    / // /   / /| |
 / _, _/ /_/ / /_/ / / / / /___     / / / ___ |/ /_/ / /___/ /___   / ____/ /_/ / /_/ / /____/ // /___/ ___ |
/_/ |_|\____/\____/ /_/ /_____/    /_/ /_/  |_/_____/_____/_____/  /_/    \____/_____/_____/___/\____/_/  |_|                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          
ARTE_ASCII
echo "========================================================================================================================================"

    # Criando uma tabela de rotas para o VPC criado, e associando ela à subrede pública, para que as instâncias na subrede pública possam acessar a internet através do Internet Gateway criado
    echo -e "\e[32m(!) - Criando tabela de rotas pública...\e[0m\n"
    ROTA_PUBLICA_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rota-publica-arandu}]' --query 'RouteTable.RouteTableId' --output text)

    # Criando uma rota na tabela de rotas criada, para que o tráfego destinado à internet (0.0.0.0/0) e seja encaminhado para o Internet Gateway
    echo -e "\e[32m(!) - Criando rota para internet...\e[0m\n"
    aws ec2 create-route --route-table-id $ROTA_PUBLICA_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $INTERNET_GATEWAY_ID

    # Associando a tabela de rotas criada à subrede pública, para que as instâncias na subrede pública possam acessar a internet através do Internet Gateway criado
    echo -e "\e[32m(!) - Associando tabela de rotas à subrede pública...\e[0m\n"
    aws ec2 associate-route-table --route-table-id $ROTA_PUBLICA_ID --subnet-id $SUBNET_PUBLICA

cat <<'ARTE_ASCII'                                                                                                                                     
    _   _____  ______
   / | / /   |/_  __/
  /  |/ / /| | / /   
 / /|  / ___ |/ /    
/_/ |_/_/  |_/_/                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
ARTE_ASCII
echo "========================================================================================================================================"

    echo -e "\e[32m(!) - Alocando endereço elástico para o NAT Gateway...\e[0m\n"
    IP_ELASTICO_NAT_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

echo -e "\e[32m(!) - Criando NAT Gateway...\e[0m\n"
NAT_ID=$(aws ec2 create-nat-gateway \
--subnet-id $SUBNET_PUBLICA \
--allocation-id $IP_ELASTICO_NAT_ID \
--tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=nat-arandu}]' \
--query 'NatGateway.NatGatewayId' \
--output text)

    # Espera o NAT Gateway ficar disponível, para garantir que ele esteja pronto para ser usado antes de criar a rota na tabela de rotas da subrede privada
    echo -e "\e[32m(!) - Esperando NAT Gateway ficar disponível...\e[0m\n"
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

cat <<'ARTE_ASCII'                                                                                                                                                                                                                                               
    ____  ____  __  ______________   _________    ____  __    ______   ____  ____  _____    _____    ____  ___ 
   / __ \/ __ \/ / / /_  __/ ____/  /_  __/   |  / __ )/ /   / ____/  / __ \/ __ \/  _/ |  / /   |  / __ \/   |
  / /_/ / / / / / / / / / / __/      / / / /| | / __  / /   / __/    / /_/ / /_/ // / | | / / /| | / / / / /| |
 / _, _/ /_/ / /_/ / / / / /___     / / / ___ |/ /_/ / /___/ /___   / ____/ _, _// /  | |/ / ___ |/ /_/ / ___ |
/_/ |_|\____/\____/ /_/ /_____/    /_/ /_/  |_/_____/_____/_____/  /_/   /_/ |_/___/  |___/_/  |_/_____/_/  |_|                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                
ARTE_ASCII
echo "========================================================================================================================================"

    # Criando uma tabela de rotas para o VPC criado, e associando ela à subrede privada, para que as instâncias na subrede privada possam acessar a internet através do NAT Gateway criado
    echo -e "\e[32m(!) - Criando tabela de rotas privada...\e[0m\n"
    ROTA_PRIVADA_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rota-privada-arandu}]' --query 'RouteTable.RouteTableId' --output text)

    # Criando uma rota na tabela de rotas criada, para que o tráfego destinado à internet (
    echo -e "\e[32m(!) - Criando rota para internet...\e[0m\n"
    aws ec2 create-route --route-table-id $ROTA_PRIVADA_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID

    # Associando a tabela de rotas criada à subrede privada, para que as instâncias na subrede privada possam acessar a internet através do NAT Gateway criado
    echo -e "\e[32m(!) - Associando tabela de rotas à subrede privada...\e[0m\n"
    aws ec2 associate-route-table --route-table-id $ROTA_PRIVADA_ID --subnet-id $SUBNET_PRIVADA
    aws ec2 associate-route-table --subnet-id $SUBNET_DB --route-table-id $ROTA_PRIVADA_ID


cat <<'ARTE_ASCII'                                                                                                                                                          
   _____ ______________  ______  ____________  __   __________  ____  __  ______  _____
  / ___// ____/ ____/ / / / __ \/  _/_  __/\ \/ /  / ____/ __ \/ __ \/ / / / __ \/ ___/
  \__ \/ __/ / /   / / / / /_/ // /  / /    \  /  / / __/ /_/ / / / / / / / /_/ /\__ \ 
 ___/ / /___/ /___/ /_/ / _, _// /  / /     / /  / /_/ / _, _/ /_/ / /_/ / ____/___/ / 
/____/_____/\____/\____/_/ |_/___/ /_/     /_/   \____/_/ |_|\____/\____/_/    /____/                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
ARTE_ASCII
echo "========================================================================================================================================"

echo -e "\e[32m(!) - Criando security group do frontend...\e[0m\n"
SG_FRONTEND=$(aws ec2 create-security-group --group-name arandu-sg-frontend --description "SG Frontend Arandu" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 create-tags --resources $SG_FRONTEND --tags Key=Name,Value=arandu-sg-frontend

echo -e "\e[32m(!) - Criando security group do backend...\e[0m\n"

SG_BACKEND=$(aws ec2 create-security-group --group-name arandu-sg-backend --description "SG Backend Arandu" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_BACKEND --tags Key=Name,Value=arandu-sg-backend
aws ec2 authorize-security-group-ingress --group-id $SG_BACKEND --protocol tcp --port 8080 --source-group $SG_FRONTEND
aws ec2 authorize-security-group-ingress --group-id $SG_BACKEND --protocol tcp --port 22 --source-group $SG_FRONTEND

echo -e "\e[32m(!) - Criando security group do banco...\e[0m\n"
SG_DB=$(aws ec2 create-security-group --group-name arandu-sg-db --description "SG Database Arandu" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_DB --tags Key=Name,Value=arandu-sg-db
aws ec2 authorize-security-group-ingress --group-id $SG_DB --protocol tcp --port 3306 --source-group $SG_BACKEND
aws ec2 authorize-security-group-ingress --group-id $SG_DB --protocol tcp --port 22 --source-group $SG_BACKEND


cat <<'ARTE_ASCII'  
    _____   _____________ //|  _   _______________   _____
   /  _/ | / / ___/_  __/|/|| / | / / ____/  _/   | / ___/
   / //  |/ /\__ \ / / / _ | /  |/ / /    / // /| | \__ \ 
 _/ // /|  /___/ // / / __ |/ /|  / /____/ // ___ |___/ / 
/___/_/ |_//____//_/ /_/ |_/_/ |_/\____/___/_/  |_/____/                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                
ARTE_ASCII
echo "========================================================================================================================================"

    # Salvando ID da imagem Ubuntu para criação das instâncias
    echo -e "\e[32m(!) - Selecionando imagem AMI Ubuntu para criação das instâncias...\e[0m\n"
    IMAGEM_ID=$(aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text)

    # Criando par de chaves
    echo -e "\e[32m(!) - Verificando se a chave .pem já existe...\e[0m\n"

    if [ -f "arandu-key.pem" ]; then
        aws ec2 delete-key-pair --key-name arandu-key 2>/dev/null || true
        echo -e "\e[31m(!) - Arquivo arandu-key.pem já existe. Deletando...\e[0m\n"
        rm -f arandu-key.pem
    fi
    
    echo -e "\e[32m(!) - Criando par de chaves...\e[0m\n"
    aws ec2 create-key-pair --key-name arandu-key --key-type rsa --query 'KeyMaterial' --output text > arandu-key.pem

    # Alterando as permissões do arquivo da chave privada para que apenas o proprietário possa ler, o que é necessário para usar a chave com o SSH
    chmod 400 arandu-key.pem

# Criando uma instância EC2 na subrede privada do VPC criado, usando a imagem AMI do Ubuntu 22.04, o tipo de instância t2.micro, a chave de acesso arandu-key, o grupo de segurança criado e a tag "Name" com o valor "ec2-arandu-privada"
echo -e "\e[32m(!) - Criando instância EC2 pública do frontend...\e[0m\n"
aws ec2 run-instances \
--image-id $IMAGEM_ID \
--instance-type t2.micro \
--key-name arandu-key \
--subnet-id $SUBNET_PUBLICA \
--private-ip-address 10.0.1.10 \
--security-group-ids $SG_FRONTEND \
--associate-public-ip-address \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-frontend},{Key=Role,Value=frontend}]'

# Criando a instância na subrede privada, sem associar um IP público, o que significa que ela só poderá ser acessada através da instância pública, utilizando o SSH com a chave privada criada anteriormente
echo -e "\e[32m(!) - Criando instância EC2 privada do backend...\e[0m\n"
aws ec2 run-instances \
--image-id $IMAGEM_ID \
--instance-type t2.micro \
--key-name arandu-key \
--subnet-id $SUBNET_PRIVADA \
--private-ip-address 10.0.2.10 \
--security-group-ids $SG_BACKEND \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-backend},{Key=Role,Value=backend}]'

# Criando a instância na subrede privada de banco, sem associar um IP público, o que significa que ela só poderá ser acessada através da instância pública, utilizando o SSH com a chave privada criada anteriormente, e essa instância será utilizada para rodar o banco de dados, por isso o nome "ec2-arandu-db"
echo -e "\e[32m(!) - Criando instância EC2 banco...\e[0m\n"
aws ec2 run-instances \
--image-id $IMAGEM_ID \
--instance-type t2.micro \
--key-name arandu-key \
--subnet-id $SUBNET_DB \
--private-ip-address 10.0.3.10 \
--security-group-ids $SG_DB \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-db},{Key=Role,Value=db}]'

    echo -e "\e[32mInfraestrutura criada com sucesso!\e[0m"

else
    echo -e "\e[31mVPC já existe: $VPC_ID\e[0m"
    echo "1 - Manter infraestrutura"
    echo "2 - Deletar TUDO da VPC"
    read opcao

    if [[ "$opcao" == "2" ]]; then

        echo -e "\e[32m(!) - Encerrando instâncias...\e[0m\n"

        INSTANCIAS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[].Instances[].InstanceId" --output text)

        if [ -n "$INSTANCIAS" ]; then
            aws ec2 terminate-instances --instance-ids $INSTANCIAS
            aws ec2 wait instance-terminated --instance-ids $INSTANCIAS
        fi


        echo -e "\e[32m(!) - Removendo NAT Gateway...\e[0m\n"

        NAT_IDS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[].NatGatewayId" --output text)

        for nat in $NAT_IDS; do
            if [[ "$EIP_ALLOC" != "None" && -n "$EIP_ALLOC" ]]; then
                aws ec2 release-address --allocation-id $EIP_ALLOC 2>/dev/null || true
            fi

            aws ec2 delete-nat-gateway --nat-gateway-id $nat
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids $nat

            if [ -n "$EIP_ALLOC" ]; then
                aws ec2 release-address --allocation-id $EIP_ALLOC 2>/dev/null || true
            fi
        done


        echo -e "\e[32m(!) - Removendo tabelas de rota...\e[0m\n"

        ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
        --output text)

        for rt in $ROUTE_TABLES; do

            ASSOCIATIONS=$(aws ec2 describe-route-tables \
            --route-table-ids $rt \
            --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text)

            for assoc in $ASSOCIATIONS; do
                aws ec2 disassociate-route-table --association-id $assoc
            done

            aws ec2 delete-route-table --route-table-id $rt
        done


        echo -e "\e[32m(!) - Removendo Internet Gateway...\e[0m\n"

        IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text)

        if [ -n "$IGW" ]; then
            aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
            aws ec2 delete-internet-gateway --internet-gateway-id $IGW
        fi


        echo -e "\e[32m(!) - Removendo subnets...\e[0m\n"

        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[].SubnetId" --output text)

        for s in $SUBNETS; do
            aws ec2 delete-subnet --subnet-id $s
        done


        echo -e "\e[32m(!) - Removendo interfaces de rede...\e[0m\n"

        ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)

        for eni in $ENIS; do
            aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null || true
        done

        echo -e "\e[32m(!) - Removendo security groups...\e[0m\n"

        SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

        echo -e "\e[32m(!) - Limpando regras de security groups...\e[0m\n"

        for sg in $SG; do

            INGRESS_RULES=$(aws ec2 describe-security-groups \
            --group-ids $sg \
            --query "SecurityGroups[].IpPermissions" \
            --output json)

            if [ "$INGRESS_RULES" != "[]" ]; then
                aws ec2 revoke-security-group-ingress \
                --group-id $sg \
                --ip-permissions "$INGRESS_RULES" 2>/dev/null || true
            fi


            EGRESS_RULES=$(aws ec2 describe-security-groups \
            --group-ids $sg \
            --query "SecurityGroups[].IpPermissionsEgress" \
            --output json)

            if [ "$EGRESS_RULES" != "[]" ]; then
                aws ec2 revoke-security-group-egress \
                --group-id $sg \
                --ip-permissions "$EGRESS_RULES" 2>/dev/null || true
            fi

        done

        echo -e "\e[32m(!) - Deletando security groups...\e[0m"

        for sg in $SG; do
            aws ec2 delete-security-group --group-id $sg 2>/dev/null || true
        done

        echo -e "\e[32m(!) - Removendo key pair...\e[0m\n"

        aws ec2 delete-key-pair --key-name arandu-key 2>/dev/null || true
        rm -f arandu-key.pem


        echo -e "\e[32m(!) - Deletando VPC...\e[0m\n"

        aws ec2 wait vpc-available --vpc-ids $VPC_ID

        sleep 180

        aws ec2 delete-vpc --vpc-id $VPC_ID


        echo -e "\e[32mInfraestrutura removida com sucesso!\e[0m"

    fi
fi
