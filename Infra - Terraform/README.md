# Infraestrutura Terraform — Arandu

Configuracao declarativa em Terraform para provisionamento da infraestrutura na AWS.

## Recursos Provisionados

- VPC 10.0.0.0/16 com 2 subnets publicas e 3 privadas
- Internet Gateway e NAT Gateway para comunicacao de rede
- Application Load Balancer com roteamento de rotas de API para o Backend e padrao para o Frontend
- Instancias EC2 para 2 Frontends (Nginx) e 1 Backend (Spring Boot)
- RDS MySQL 8.0 na rede privada
- Sistema de arquivos EFS para sincronizacao dos assets do Frontend
- Bucket S3 para documentos e buckets da arquitetura medalhao (Bronze, Silver, Gold)
- Security Groups e NACLs
- Dashboard de monitoramento no CloudWatch

## Estrutura de Arquivos

| Arquivo | Descricao |
|---|---|
| `providers.tf` | Providers AWS, Random, TLS e Local |
| `variables.tf` | Variaveis de rede, instancias, banco e storage |
| `vpc.tf` | VPC, Subnets, Gateways, Tabelas de Rota e NACL |
| `security_groups.tf` | Regras de firewall para ALB, Frontend, Backend, EFS e RDS |
| `iam.tf` | Role e Instance Profile para o Backend |
| `s3.tf` | Buckets S3 |
| `efs.tf` | EFS e Mount Targets |
| `key_pair.tf` | Geracao de chave SSH arandu-key.pem |
| `rds.tf` | Instancia RDS MySQL e Subnet Group |
| `compute.tf` | AMI, User Data e Instancias EC2 |
| `alb.tf` | ALB, Target Groups, Listeners e regras |
| `cloudwatch.tf` | Dashboard do CloudWatch |
| `outputs.tf` | Endpoints, IPs e comandos de acesso |

## Como Executar

1. Configurar as credenciais da AWS no terminal (`aws configure` ou variaveis de ambiente).

2. Inicializar o Terraform:
```bash
terraform init
```

3. Visualizar o plano de execucao:
```bash
terraform plan
```

4. Aplicar a configuracao:
```bash
terraform apply
```

## Acessos

Apos a aplicacao, os outputs exibirao:
- URL do ALB
- URL do Swagger
- Dashboard do CloudWatch

Para obter a senha gerada do banco ou segredo JWT:
```bash
terraform output -raw rds_password
terraform output -raw jwt_secret
```

Para conexao SSH:
```bash
ssh -i arandu-key.pem ubuntu@<IP_PUBLICO_FRONTEND>
```

## Destruir a Infraestrutura

```bash
terraform destroy
```
