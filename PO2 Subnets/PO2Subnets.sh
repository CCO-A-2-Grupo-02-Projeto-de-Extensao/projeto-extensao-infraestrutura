#!/bin/bash

# "!/bin/bash" indica qual interpretador deve ser usado para executar o script, nesse caso o bash

set -e # Faz com que o script pare a execução caso ocorra algum erro em algum comando evitando criar uma infraestrutura incompleta ou com erros

clear # Limpa o terminal


echo -e "\n\n\n" # echo é o comando mais básico, ele volta uma mensagem no terminal
# -e na frente permite que ele interprete "\" que nos casos abaixo é utilizado para dar quebra de linha e para colorir o texto com o \n e o \e[x

echo -e "\e[32m"

# << = here document, serve para passar diversas linhas de texto em um comando, nesse caso o cat que concatena as linhas, deixando elas  como se fosse um único arquivo
cat <<'ARTE ASCII' # '' define um marcador para o texto, nesse caso ARTE ASCII, que pode ser qualquer coisa, mas tem que ser a mesma coisa no início e no final
       d8888 8888888b.         d8888 888b    888 8888888b.  888     888      8888888b. 8888888 .d8888b.  8888888 88888888888     d8888 888      
      d88888 888   Y88b       d88888 8888b   888 888  "Y88b 888     888      888  "Y88b  888  d88P  Y88b   888       888        d88888 888      
     d88P888 888    888      d88P888 88888b  888 888    888 888     888      888    888  888  888    888   888       888       d88P888 888      
    d88P 888 888   d88P     d88P 888 888Y88b 888 888    888 888     888      888    888  888  888          888       888      d88P 888 888      
   d88P  888 8888888P"     d88P  888 888 Y88b888 888    888 888     888      888    888  888  888  88888   888       888     d88P  888 888      
  d88P   888 888 T88b     d88P   888 888  Y88888 888    888 888     888      888    888  888  888    888   888       888    d88P   888 888      
 d8888888888 888  T88b   d8888888888 888   Y8888 888  .d88P Y88b. .d88P      888  .d88P  888  Y88b  d88P   888       888   d8888888888 888      
d88P     888 888   T88b d88P     888 888    Y888 8888888P"   "Y88888P"       8888888P" 8888888 "Y8888P88 8888888     888  d88P     888 88888888                                                                                                                                              
ARTE ASCII
echo -e "\e[0m"
echo -e "\n\n\n"

cat <<'ARTE ASCII'                                                                                                                                                                                                               
▄█████ █████▄  ██████ ████▄  ██████ ███  ██ ▄█████ ██ ▄████▄ ██ ▄█████   ▄████▄ ██     ██ ▄█████ 
██     ██▄▄██▄ ██▄▄   ██  ██ ██▄▄   ██ ▀▄██ ██     ██ ██▄▄██ ██ ▀▀▀▄▄▄   ██▄▄██ ██ ▄█▄ ██ ▀▀▀▄▄▄ 
▀█████ ██   ██ ██▄▄▄▄ ████▀  ██▄▄▄▄ ██   ██ ▀█████ ██ ██  ██ ██ █████▀   ██  ██  ▀██▀██▀  █████▀                                                                                                                                                                                                                      
ARTE ASCII

echo "========================================================================================================================================"

# Essa parte é basicamente um AWS configure


echo -e "\e[34mJá digitou suas credenciais de acesso nas últimas 4 horas (não esqueça de verificar o tempo restante na aws)? (s/n)\e[0m"
read resposta # read lê a resposta do usuário e armazena na variável 

# Verifica a letra informa pelo usuário, se for diferente de "s", ele pede para o usuário informar as credenciais de acesso
if [[ "$resposta" != "s" ]]; then
    echo -e "\e[33mPara descobrir suas credenciais de acesso, acesse o console da AWS na web e execute o comando 'cat .aws/credentials'\e[0m"

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

    echo -e "\e[32mCredenciais cadastradas com sucessos! Execute o programa novamente e responda com a letra "s".\e[0m"
    exit 
fi

# aws (início do comando), "ec2" (serviço que vai ser usado), describe-vpcs (ação que vai ser executada) 
# --filters (opção para filtrar os resultados, nesse caso o filtro é "Name=tag:Name,Values=vpc-arandu", que significa que ele vai procurar por VPCs que tenham a tag "Name" com o valor "vpc-arandu")
# --query (opção para formatar a saída do comando, nesse caso ele vai pegar o primeiro VPC encontrado e retornar apenas o ID do VPC) 
# --output (opção para definir o formato da saída, nesse caso "text" para retornar apenas o texto do ID do VPC)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-arandu" --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then # Verifica se a variável VPC_ID é igual a "None" ou está vazia atráves do -z, o que significa que o VPC não existe, e se for o caso, ele cria o VPC
    echo -e "\n\e[31m(!) - VPC não existe\e[0m"
    echo -e "\e[33m(!) - Criando VPC...\e[0m\n"

    # aws (início do comando), "ec2" (serviço que vai ser usado), create-vpc (ação que vai ser executada) e especificações com --
    # --cidr-block (opção para definir o bloco CIDR do VPC)
    # Lembrando que CIDR é metodo de notação para definir intervalos de endereços IP, nesse caso o bloco CIDR é 192.168.0.0/24 que é o bloco de classe C, que tem 256 endereços IP disponíveis, 
    # e o /24 indica que os primeiros 24 bits do endereço IP são fixos, ou seja, os primeiros 3 octetos (192.168.0) são fixos e o último octeto (0) pode variar de 0 a 255, 
    # permitindo assim a criação de sub-redes dentro desse bloco CIDR
    # --tag-specifications (opção para definir as tags do VPC, nesse caso o nome do VPC é "vpc-arandu")
    aws ec2 create-vpc --cidr-block 192.168.0.0/24 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=vpc-arandu}]'

    # Pega o atual ID do VPC criado
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-arandu" --query "Vpcs[0].VpcId" --output text)


    echo -e "\e[33m(!) - Criando subred publica...\e[0m\n"
    # Cria subred publica dentro do VPC criado
    SUBNET_PUBLICA=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.0.0/27 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-arandu-publica}]' --query 'Subnet.SubnetId' --output text)

    echo -e "\e[33m(!) - Criando subred privada...\e[0m\n"
    # Cria subred privada dentro do VPC criado
    SUBNET_PRIVADA=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.0.32/27 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-arandu-privada}]' --query 'Subnet.SubnetId' --output text)

    # Ambas subredes estão com bloco CIDR de classe C, com 32 endereços IP disponíveis

    # Criando par de chaves
    echo -e "\e[33m(!) - Verificando se a chave .pem já existe...\e[0m\n"

    if [ -f "arandu-key.pem" ]; then
        echo -e "\e[31m(!) - Arquivo arandu-key.pem já existe. Deletando...\e[0m\n"
        rm -f arandu-key.pem
    fi

    echo -e "\e[33m(!) - Criando par de chaves...\e[0m\n"
    aws ec2 create-key-pair --key-name arandu-key --key-type rsa --query 'KeyMaterial' --output text > arandu-key.pem

    # Alterando as permissões do arquivo da chave privada para que apenas o proprietário possa ler, o que é necessário para usar a chave com o SSH
    chmod 400 arandu-key.pem

    # Criando security group
    echo -e "\e[33m(!) - Criando security group...\e[0m\n"
    SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name arandu-sg --description "security group arandu" --vpc-id $VPC_ID --query 'GroupId' --output text)

    # Liberando a porta 22 (SSH) para acesso remoto
    echo -e "\e[33m(!) - Liberando porta 22 (SSH)...\e[0m\n"
    aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

    # Modifica a subrede pública para que as instâncias lançadas nela recebam um IP público automaticamente
    echo -e "\e[33m(!) - Modificando atributo da subrede pública para atribuir IPs públicos automaticamente...\e[0m\n"
    aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLICA --map-public-ip-on-launch 

    echo -e "\e[33m(!) - Selecionando imagem AMI Ubuntu para criação das instâncias...\e[0m\n"
    IMAGEM_ID=$(aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text)

# Criando uma instância EC2 na subrede privada do VPC criado, usando a imagem AMI do Ubuntu 22.04, o tipo de instância t2.micro, a chave de acesso arandu-key, o grupo de segurança criado e a tag "Name" com o valor "ec2-arandu-privada"
echo -e "\e[33m(!) - Criando instância EC2 pública...\e[0m\n"
aws ec2 run-instances \
--image-id $IMAGEM_ID \
--instance-type t2.micro \
--key-name arandu-key \
--subnet-id $SUBNET_PUBLICA \
--security-group-ids $SECURITY_GROUP_ID \
--associate-public-ip-address \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-publica}]'

# Criando a instância na subrede privada, sem associar um IP público, o que significa que ela só poderá ser acessada através da instância pública, utilizando o SSH com a chave privada criada anteriormente
echo -e "\e[33m(!) - Criando instância EC2 privada...\e[0m\n"
aws ec2 run-instances \
--image-id $IMAGEM_ID \
--instance-type t2.micro \
--key-name arandu-key \
--subnet-id $SUBNET_PRIVADA \
--security-group-ids $SECURITY_GROUP_ID \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-arandu-privada}]'

    # Criando um Internet Gateway, que é um componente que permite a comunicação entre o VPC e a internet, e associando ele ao VPC criado
    echo -e "\e[33m(!) - Criando Internet Gateway...\e[0m\n"
    INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=internet-gateway-arandu}]' --query 'InternetGateway.InternetGatewayId' --output text)

    # Associando o Internet Gateway ao VPC criado
    echo -e "\e[33m(!) - Associando Internet Gateway ao VPC...\e[0m\n"
    aws ec2 attach-internet-gateway --internet-gateway-id $INTERNET_GATEWAY_ID --vpc-id $VPC_ID

    # Criando uma tabela de rotas para o VPC criado, e associando ela à subrede pública, para que as instâncias na subrede pública possam acessar a internet através do Internet Gateway criado
    echo -e "\e[33m(!) - Criando tabela de rotas pública...\e[0m\n"
    ROTA_PUBLICA_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rota-publica-arandu}]' --query 'RouteTable.RouteTableId' --output text)

    # Criando uma rota na tabela de rotas criada, para que o tráfego destinado à internet (0.0.0.0/0) e seja encaminhado para o Internet Gateway
    echo -e "\e[33m(!) - Criando rota para internet...\e[0m\n"
    aws ec2 create-route --route-table-id $ROTA_PUBLICA_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $INTERNET_GATEWAY_ID

    # Associando a tabela de rotas criada à subrede pública, para que as instâncias na subrede pública possam acessar a internet através do Internet Gateway criado
    echo -e "\e[33m(!) - Associando tabela de rotas à subrede pública...\e[0m\n"
    aws ec2 associate-route-table --route-table-id $ROTA_PUBLICA_ID --subnet-id $SUBNET_PUBLICA

    echo -e "\e[33m(!) - Alocando endereço elástico para o NAT Gateway...\e[0m\n"
    IP_ELASTICO_NAT_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

echo -e "\e[33m(!) - Criando NAT Gateway...\e[0m\n"
NAT_ID=$(aws ec2 create-nat-gateway \
--subnet-id $SUBNET_PUBLICA \
--allocation-id $IP_ELASTICO_NAT_ID \
--tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=nat-arandu}]' \
--query 'NatGateway.NatGatewayId' \
--output text)

    # Espera o NAT Gateway ficar disponível, para garantir que ele esteja pronto para ser usado antes de criar a rota na tabela de rotas da subrede privada
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

    # Criando uma tabela de rotas para o VPC criado, e associando ela à subrede privada, para que as instâncias na subrede privada possam acessar a internet através do NAT Gateway criado
    echo -e "\e[33m(!) - Criando tabela de rotas privada...\e[0m\n"
    ROTA_PRIVADA_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rota-privada-arandu}]' --query 'RouteTable.RouteTableId' --output text)

    # Criando uma rota na tabela de rotas criada, para que o tráfego destinado à internet (
    echo -e "\e[33m(!) - Criando rota para internet...\e[0m\n"
    aws ec2 create-route --route-table-id $ROTA_PRIVADA_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID

    # Associando a tabela de rotas criada à subrede privada, para que as instâncias na subrede privada possam acessar a internet através do NAT Gateway criado
    echo -e "\e[33m(!) - Associando tabela de rotas à subrede privada...\e[0m\n"
    aws ec2 associate-route-table --route-table-id $ROTA_PRIVADA_ID --subnet-id $SUBNET_PRIVADA

    echo -e "\e[32mInfraestrutura criada com sucesso!\e[0m"

else
    echo -e "\e[31mVPC já existe: $VPC_ID\e[0m"
    echo "1 - Manter infraestrutura"
    echo "2 - Deletar TUDO da VPC"
    read opcao

    # Verifica a opção escolhida pelo usuário, se for 1, ele mantém a infraestrutura e encerra o script, se for 2, ele executa os comandos para deletar toda a infraestrutura criada, incluindo as instâncias, o NAT Gateway, o Internet Gateway, as subredes, as tabelas de rotas, o security group e o par de chaves
    if [[ "$opcao" == "2" ]]; then

        # Para encerrar as instâncias, ele primeiro pega o ID de todas as instâncias que estão rodando dentro do VPC criado
        echo -e "\e[33m(!) - Encerrando instâncias...\e[0m\n"
        INSTANCIAS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query "Reservations[].Instances[].InstanceId" --output text)

        # Verifica se a variável INSTANCIAS não está vazia, o que significa que existem instâncias rodando dentro do VPC, e se for o caso, ele encerra as instâncias
        if [ -n "$INSTANCIAS" ]; then
            aws ec2 terminate-instances --instance-ids $INSTANCIAS
            aws ec2 wait instance-terminated --instance-ids $INSTANCIAS
        fi

        # Depois de encerrar as instâncias, ele espera 30 segundos para garantir que as instâncias sejam encerradas completamente antes de tentar deletar os outros recursos, como o NAT Gateway e o Internet Gateway, que dependem das instâncias para serem usados
        echo -e "\e[33m(!) - Removendo NAT Gateway...\e[0m\n"
        NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[].NatGatewayId" --output text)

        if [ -n "$NAT_ID" ]; then
            aws ec2 delete-nat-gateway --nat-gateway-id $NAT_ID
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_ID # Depois de esperar o NAT Gateway ser deletado, ele espera mais 30 segundos para garantir que o NAT Gateway seja deletado completamente antes de tentar deletar o Internet Gateway, que depende do NAT Gateway para ser usado
        fi
        
        
        echo -e "\e[33m(!) - Liberando Elastic IP...\e[0m\n"
        EIP_ALLOC=$(aws ec2 describe-addresses --query "Addresses[].AllocationId" --output text) # Pega o ID de alocação do Elastic IP criado para o NAT Gateway, para que ele possa ser liberado depois que o NAT Gateway for deletado, já que um Elastic IP só pode ser associado a um recurso, como uma instância ou um NAT Gateway, e se o recurso for deletado, o Elastic IP fica associado a nada, e para evitar cobranças desnecessárias, é importante liberar o Elastic IP quando ele não estiver mais sendo usado

        if [ -n "$EIP_ALLOC" ]; then # Verifica se a variável EIP_ALLOC não está vazia, o que significa que existe um Elastic IP alocado, e se for o caso, ele libera o Elastic IP
            aws ec2 release-address --allocation-id $EIP_ALLOC
        fi


        # Removendo rotas de acordo com a VPC
        echo -e "\e[33m(!) - Removendo tabelas de rota...\e[0m\n"

        ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
        --output text)

        for rt in $ROUTE_TABLES; do

            # Pega IDs das associações não principais
            ASSOCIATIONS=$(aws ec2 describe-route-tables \
            --route-table-ids $rt \
            --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text)

            # Remove associações
            for assoc in $ASSOCIATIONS; do
                aws ec2 disassociate-route-table --association-id $assoc
            done

            # Deleta rotas
            aws ec2 delete-route-table --route-table-id $rt

        done


        echo -e "\e[33m(!) - Removendo Internet Gateway...\e[0m\n"
        # Para remover o Internet Gateway, ele primeiro pega o ID do Internet Gateway associado ao VPC criado, e se existir um Internet Gateway associado, ele desanexa o Internet Gateway do VPC e depois deleta o Internet Gateway, lembrando que um Internet Gateway só pode ser associado a um VPC, e para deletar um Internet Gateway, ele precisa ser desanexado do VPC primeiro
        IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text)

        # Verifica se a variável IGW não está vazia, o que significa que existe um Internet Gateway associado ao VPC, e se for o caso, ele desanexa o Internet Gateway do VPC e depois deleta o Internet Gateway
        if [ -n "$IGW" ]; then
            aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
            aws ec2 delete-internet-gateway --internet-gateway-id $IGW
        fi


        echo -e "\e[33m(!) - Removendo subnets...\e[0m\n"
        # Para remover as subredes, ele primeiro pega o ID de todas as subredes associadas ao VPC criado, e se existirem subredes associadas, ele deleta as subredes, lembrando que para deletar uma subrede, ela precisa estar vazia, ou seja, não pode ter instâncias rodando dentro dela, e como as instâncias já foram encerradas no início do processo de deleção da infraestrutura, as subredes já estão vazias e podem ser deletadas sem problemas
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[].SubnetId" --output text)
        
        # Verifica se a variável SUBNETS não está vazia, o que significa que existem subredes associadas ao VPC, e se for o caso, ele deleta as subredes
        for s in $SUBNETS; do
            aws ec2 delete-subnet --subnet-id $s
        done


        echo -e "\e[33m(!) - Removendo security group...\e[0m\n"

        # Para remover o security group, ele primeiro pega o ID do security group criado dentro do VPC, e se existir um security group criado, ele deleta o security group, lembrando que o security group padrão do VPC não pode ser deletado, por isso o filtro para pegar apenas os security groups que não são o padrão
        SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

        # Verifica se a variável SG não está vazia, o que significa que existe um security group criado dentro do VPC, e se for o caso, ele deleta o security group
        if [ -n "$SG" ]; then
            aws ec2 delete-security-group --group-id $SG
        fi

        echo -e "\e[33m(!) - Removendo key pair...\e[0m\n"

        # Para remover o par de chaves, ele deleta o par de chaves criado, e depois remove o arquivo da chave privada do sistema, lembrando que para deletar um par de chaves, ele precisa ser deletado na AWS primeiro, para garantir que ele não seja mais usado para acessar as instâncias, e depois o arquivo da chave privada pode ser removido do sistema para evitar confusões ou acessos indesejados no futuro
        aws ec2 delete-key-pair --key-name arandu-key || true
        rm -f arandu-key.pem


        echo -e "\e[33m(!) - Deletando VPC...\e[0m\n"

        # Para deletar o VPC, ele deleta o VPC criado, lembrando que para deletar um VPC, ele precisa estar vazio, ou seja, não pode ter instâncias rodando dentro dele, não pode ter subredes associadas, não pode ter Internet Gateway associado, e não pode ter tabelas de rotas associadas, e como todos esses recursos já foram deletados no processo de deleção da infraestrutura, o VPC já está vazio e pode ser deletado sem problemas
        aws ec2 delete-vpc --vpc-id $VPC_ID

        echo -e "\e[32mInfraestrutura removida com sucesso!\e[0m"

    fi
fi

