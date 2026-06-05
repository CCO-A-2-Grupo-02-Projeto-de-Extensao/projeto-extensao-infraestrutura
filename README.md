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
| EC2 Backend ×1 | `t3.micro`, Docker Spring Boot (subnet privada) |
| ALB | Roteamento por path para frontend e backend |

---

## Pré-requisitos

- AWS CLI instalado e no PATH
- Bash (Linux, macOS ou WSL no Windows)
- Credenciais AWS com permissões para EC2, EFS, RDS, S3, IAM e ELB
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

## Atualizar o frontend

Os arquivos do frontend ficam armazenados no EFS em `/mnt/efs/frontend/`.  
Na primeira execução de cada instância, os arquivos são copiados automaticamente da imagem Docker.

Para forçar atualização com uma nova versão da imagem:

```bash
# Na instância frontend (via SSH a partir do jump host)
rm /mnt/efs/frontend/.deployed
docker stop frontend && docker rm frontend
# O container sobe novamente pelo restart policy e repopula o EFS
docker run -d --name frontend --restart unless-stopped \
  -p 80:80 \
  -v /mnt/efs/frontend:/usr/share/nginx/html:ro \
  pedrobarbosa996/arandu_digital:frontend
```

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
