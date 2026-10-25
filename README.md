# Infraestrutura AWS — Arandu Digital

Repositório com o script de provisionamento da infraestrutura AWS do projeto Arandu Digital.  
Grupo 02 – CCO A2 SPTech 2026

---

## Objetivo

Provisionar toda a infraestrutura necessária para o deploy do Arandu Digital na AWS com um único script:  
rede, banco de dados, armazenamento, instâncias e balanceador de carga.

---

## Tecnologias

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Shell](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![MySQL](https://img.shields.io/badge/mysql-4479A1.svg?style=for-the-badge&logo=mysql&logoColor=white)

---

## Arquitetura

```
Internet
    │
    ▼
  ALB (público)
  ├── /* ──────────────────► EC2 Frontend 1 (us-east-1a, porta 80)  ─┐
  │                                                                    ├── EFS (frontend files)
  ├── /* ──────────────────► EC2 Frontend 2 (us-east-1b, porta 80)  ─┘
  │
  ├── /swagger-ui*  ┐
  ├── /v3/api-docs* │
  ├── /auth*        ├──────► EC2 Backend (subnet privada, porta 8080)
  ├── /usuarios*    │              │
  ├── /documentos*  │              ├── RDS MySQL (subnet privada)
  └── /...outros* ──┘              └── S3 (documentos)
```

**Recursos criados (us-east-1):**

| Recurso | Detalhes |
|---|---|
| VPC | `10.0.0.0/16` |
| Subnets | 2 públicas (frontend), 1 privada (backend), 2 privadas (DB) |
| Internet Gateway + NAT Gateway | Acesso externo e saída para instâncias privadas |
| NACL + 5 Security Groups | ALB, frontend, EFS, backend, DB |
| EFS | Armazena os arquivos do frontend, montado nas 2 instâncias |
| S3 | `arandu-documentos-<account_id>` — documentos do backend |
| RDS MySQL 8.0 | `db.t3.micro`, banco `bdClubeDesbravadores` |
| EC2 Frontend ×2 | `t3.micro`, Docker nginx servindo do EFS |
| EC2 Backend ×1 | `t3.micro`, Docker Spring Boot + RabbitMQ (subnet privada) |
| ECR | `arandu_digital:backend` e `:frontend`, de onde as EC2 puxam as imagens |
| ALB | Roteamento por path para frontend e backend |

---

## Pré-requisitos

- AWS CLI instalado e no PATH
- Docker rodando na máquina local (o script copia as imagens do Docker Hub para o ECR)
- Bash (Linux, macOS ou WSL no Windows)
- Credenciais AWS com permissões para EC2, EFS, RDS, S3, IAM, ELB, ECR e SSM
- Par de chaves **não** é necessário criar antes — o script cria automaticamente

---

## Como usar

### 1. Clonar o repositório

```bash
git clone https://github.com/CCO-A-2-Grupo-02-Projeto-de-Extensao/projeto-extensao-infraestrutura.git
cd projeto-extensao-infraestrutura
chmod +x infra_arandu.sh
```

### 2. Executar o script

```bash
./infra_arandu.sh
```

O script pergunta se as credenciais já foram configuradas nas últimas 4 horas.  
Se não, solicita **Access Key ID**, **Secret Access Key** e **Session Token** (AWS Academy).

### 3. Aguardar o provisionamento

O processo leva aproximadamente **10–15 minutos** (o RDS é o passo mais demorado).  
Ao final, o script exibe a URL da aplicação e do Swagger.

### 4. Deletar a infraestrutura

Ao rodar o script novamente com a VPC já existente, ele oferece a opção de deletar tudo.

---

## Imagens no ECR e atualização

O CI de cada repo publica a imagem no Docker Hub (`pedrobarbosa996/arandu_digital:backend` e `:frontend`).
Ao provisionar, o script cria o repositório `arandu_digital` no ECR da conta que está rodando e copia as duas imagens para lá; as EC2 puxam do ECR usando o instance profile.
Como cada integrante usa a própria conta do AWS Academy, cada um tem o próprio ECR.

Para publicar uma versão nova depois que o CI terminar, rode o script com a infraestrutura de pé e escolha a opção **4 - Atualizar imagens**. Ela:

1. copia de novo as imagens do Docker Hub para o ECR;
2. executa `/opt/arandu/deploy.sh` em cada instância via SSM, que puxa a imagem do ECR e recria o container (no frontend, também recopia os arquivos para o EFS).

Sem SSH e sem recriar a infraestrutura. O mesmo `deploy.sh` pode ser rodado à mão dentro da instância.

---

## Acesso às instâncias

A chave SSH `arandu-key.pem` é gerada na pasta local ao rodar o script.

```bash
# Frontend (subnet pública — acesso direto)
ssh -i arandu-key.pem ubuntu@<IP_PUBLICO_FRONTEND>

# Backend (subnet privada — via jump host)
ssh -i arandu-key.pem -J ubuntu@<IP_PUBLICO_FRONTEND> ubuntu@10.0.2.10
```

---

## Observações

- O repositório do backend precisa ser **público** para o `user-data` baixar o SQL de inicialização do banco.
- Em ambiente AWS Academy, o script detecta e reutiliza o `LabInstanceProfile` automaticamente.
- O script é idempotente no ponto de entrada: se a VPC já existir, oferece a opção de deletar.

---

## Equipe

Grupo 02 – CCO A2 SPTech 2026

- Ana Luiza Santos Roberto
- Lucas Hideaki Tsuzuku
- Pedro Cesar Abramo de Almeida
- Pedro Claudino Barbosa
- Pedro Henrique Maciel Vieira do Amaral
- Vinicius Rocha de Barros
