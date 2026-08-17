# Infraestrutura Arandu — Terraform

Este diretório contém a conversão completa e declarativa da infraestrutura AWS do projeto **Arandu** (originalmente provisionada via script shell `infra_arandu.sh`), utilizando **Terraform**.

---

## 🏛 Arquitetura Provisionada

- **VPC Customizada**: Bloco `10.0.0.0/16` com 5 subnets:
  - 2 Subnets públicas (`10.0.1.0/24` e `10.0.4.0/24`) distribuídas em `us-east-1a` e `us-east-1b` (Multi-AZ).
  - 3 Subnets privadas (`10.0.2.0/24` para backend e `10.0.3.0/24`, `10.0.5.0/24` para RDS).
- **Internet Gateway & NAT Gateway**: Roteamento público para os frontends/ALB e saída segura para a internet através do NAT Gateway na subnet pública.
- **NACL & Security Groups**: Regras de isolamento em camadas (ALB → Frontends → Backend → MySQL).
- **Armazenamento**:
  - **AWS EFS**: Volume compartilhado para servir os assets estáticos do Frontend entre as duas instâncias.
  - **AWS S3**: Bucket exclusivo por conta para armazenamento seguro de documentos com bloqueio de acesso público.
- **Banco de Dados**:
  - **Amazon RDS MySQL 8.0**: Instância `db.t3.micro` isolada na rede privada.
- **Computação (EC2)**:
  - **2 Instâncias Frontend**: Ubuntu 22.04 LTS rodando Nginx via Docker com montagem NFS/EFS.
  - **1 Instância Backend**: Ubuntu 22.04 LTS rodando API Spring Boot em Docker, conectando ao RDS e S3. Executa a carga inicial do banco através do script SQL oficial no boot.
- **Application Load Balancer (ALB)**:
  - Distribuição de carga pública na porta 80 entre as instâncias de frontend.
  - Regras de roteamento por path (`/swagger-ui*`, `/v3/api-docs*`, `/auth*`, `/usuarios*`, etc.) enviando requisições diretamente ao Target Group do Backend.
- **Observabilidade**:
  - **CloudWatch Dashboard**: Painel centralizado monitorando CPU das EC2s, requisições/latência/erros 4xx/5xx do ALB e saúde/conexões do RDS.
- **Acesso SSH Seguro**: Geração e exportação automática da chave RSA `arandu-key.pem`.

---

## 📁 Estrutura dos Arquivos

| Arquivo | Descrição |
|---|---|
| `providers.tf` | Configuração dos providers AWS, Random, TLS e Local |
| `variables.tf` | Definição de variáveis, subnets, imagens Docker e parâmetros padrão |
| `vpc.tf` | VPC, Subnets, Internet Gateway, NAT Gateway, Tabelas de Rota e NACL |
| `security_groups.tf` | Definição dos 5 Security Groups e suas regras de firewall |
| `iam.tf` | Role e Instance Profile para o Backend acessar o S3 (compatível com AWS Academy) |
| `s3.tf` | Bucket S3 para documentos com bloqueio público |
| `efs.tf` | File system EFS e mount targets nas subnets públicas |
| `key_pair.tf` | Geração do par de chaves SSH e exportação de `arandu-key.pem` |
| `rds.tf` | Subnet group e instância RDS MySQL 8.0 |
| `compute.tf` | Lookup de AMI Ubuntu, user data scripts e instâncias EC2 |
| `alb.tf` | ALB, Target Groups de Frontend e Backend, Listeners e regras de path |
| `cloudwatch.tf` | Dashboard de métricas unificado no CloudWatch |
| `outputs.tf` | URLs de acesso, DNS do ALB, Swagger, IPs e comandos SSH |
| `terraform.tfvars.example` | Exemplo de sobrescrita de variáveis |

---

## 🚀 Como Executar

### 1. Configurar Credenciais AWS
Certifique-se de que suas credenciais estão configuradas no terminal (`aws configure` ou via variáveis de ambiente `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`).

### 2. Inicializar o Terraform
Entre na pasta do Terraform e baixe os plugins:
```bash
cd "Infra - Terraform"
terraform init
```

### 3. Visualizar o Plano de Execução
```bash
terraform plan
```

### 4. Aplicar e Subir a Infraestrutura
```bash
terraform apply
```

*(Digite `yes` quando solicitado para confirmar a criação dos recursos).*

---

## 🔑 Acessos e Verificação

Ao término do `terraform apply`, os outputs exibirão os links principais:
- **Aplicação**: `http://<ALB_DNS>`
- **Swagger / OpenAPI**: `http://<ALB_DNS>/swagger-ui/index.html`
- **Dashboard CloudWatch**: `https://us-east-1.console.aws.amazon.com/cloudwatch/...`

Para consultar os valores sensíveis gerados (como senha do RDS e JWT Secret):
```bash
terraform output -raw rds_password
terraform output -raw jwt_secret
```

Para conectar via SSH no Frontend:
```bash
ssh -i arandu-key.pem ubuntu@<IP_PUBLICO_FRONTEND>
```

---

## 🧹 Destruir a Infraestrutura

Para remover todos os recursos criados de forma limpa e automática:
```bash
terraform destroy
```
