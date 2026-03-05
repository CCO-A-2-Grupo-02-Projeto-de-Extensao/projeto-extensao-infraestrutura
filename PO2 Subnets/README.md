📌 Procedimento de Execução e Conexão das Instâncias

1️⃣ Inicializar o Script

Execute o script responsável pela criação/configuração da infraestrutura:

sudo bash PO2Subnets.sh

2️⃣ Ajustar Permissões da Chave PEM

Por segurança, altere as permissões da chave privada:

sudo chmod 400 arandu-key.pem

3️⃣ Conectar à Instância Pública via SSH

Realize a conexão com a instância pública:

sudo ssh -i arandu-key.pem ubuntu@IP_PUBLICO

O comando completo pode ser copiado diretamente no painel da AWS (Connect → SSH Client).

4️⃣ Enviar a Chave PEM para a Instância Pública

Saia da conexão SSH e execute:

sudo scp -i arandu-key.pem arandu-key.pem ubuntu@IP_PUBLICO:/home/ubuntu/

5️⃣ Conectar à Instância Privada

* Conecte-se novamente à instância pública via SSH.
* A partir da instância pública, conecte-se à instância privada utilizando SSH.

O comando também pode ser copiado no painel da AWS.

6️⃣ Validar a Conexão na Instância Privada

Já conectado à instância privada, execute:

sudo apt update

Se o comando executar normalmente, significa que a configuração e a comunicação entre as instâncias estão funcionando corretamente.
