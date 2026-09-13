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
| `providers.tf` | Configuração dos providers AWS, Random, TLS e Local |
| `variables.tf` | Definição de variáveis, subnets, imagens Docker e parâmetros padrão |
| `vpc.tf` | VPC, Subnets, Internet Gateway, NAT Gateway, Tabelas de Rota e NACL |
| `security_groups.tf` | Definição dos 5 Security Groups e suas regras de firewall |
| `iam.tf` | Role e Instance Profile para o Backend acessar o S3 (compatível com AWS Academy) |
| `s3.tf` | Buckets S3 (documentos + medalhão), criados via AWS CLI — ver *Restrições do AWS Academy* |
| `efs.tf` | File system EFS e mount targets nas subnets públicas |
| `key_pair.tf` | Geração do par de chaves SSH e exportação de `arandu-key.pem` |
| `rds.tf` | Subnet group e instância RDS MySQL 8.0 |
| `compute.tf` | Lookup de AMI Ubuntu, user data scripts e instâncias EC2 |
| `alb.tf` | ALB, Target Groups de Frontend e Backend, Listeners e regras de path |
| `cloudwatch.tf` | Dashboard de métricas unificado no CloudWatch |
| `outputs.tf` | URLs de acesso, DNS do ALB, Swagger, IPs e comandos SSH |
| `terraform.tfvars.example` | Exemplo de sobrescrita de variáveis |

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

---

## ⚠️ Restrições do AWS Academy

O ambiente do Learner Lab tem uma Service Control Policy que muda como esta
infraestrutura precisa ser escrita. Vale ler antes de "corrigir" o `s3.tf`.

### Por que os buckets não usam `aws_s3_bucket`

A SCP nega explicitamente **`s3:GetBucketObjectLockConfiguration`**. Só essa
chamada — `get-bucket-versioning`, `get-bucket-encryption` e `get-bucket-acl`
funcionam normalmente.

O provider AWS chama essa API toda vez que lê um recurso `aws_s3_bucket`, tanto
depois de criar quanto no refresh. Como o deny é explícito em SCP, nenhuma
política IAM o sobrepõe, e não há versão do provider que a dispense: o suporte a
object lock existe desde a v2 e o comportamento é
[issue aberto desde 2019](https://github.com/hashicorp/terraform-provider-aws/issues/7550).

Na prática, com `aws_s3_bucket` no código:

- o bucket **é criado**, mas a releitura falha com `AccessDenied` e o recurso
  fica marcado como `tainted`;
- tudo que depende dele é pulado — foi assim que a EC2 do backend deixou de
  subir, por referenciar o bucket de documentos;
- `terraform plan` e `terraform destroy` passam a falhar **sempre**, porque o
  refresh relê o bucket.

Por isso os 4 buckets são criados por `terraform_data` + `local-exec` chamando a
AWS CLI, exatamente como o `infra_arandu.sh` já fazia. O `local-exec` usa
`head-bucket || create-bucket`, então adota bucket existente em vez de recriar, e
o provisioner de destroy esvazia o bucket antes de removê-lo.

**Não troque isso de volta para `aws_s3_bucket`** sem antes confirmar que a SCP
mudou:

```bash
aws s3api get-object-lock-configuration --bucket <nome-do-bucket>
```

### Se um apply falhar no meio

O estado muda quando um apply falha parcialmente. Rode `terraform plan` **antes**
do próximo apply: recurso que ficou `tainted` é destruído e recriado, e um
`-refresh=false` sozinho não evita isso. Para limpar a marca sem recriar:

```bash
terraform untaint <endereco.do.recurso>
```

Para parar de gerenciar um recurso sem apagá-lo da AWS:

```bash
terraform state rm <endereco.do.recurso>
```
