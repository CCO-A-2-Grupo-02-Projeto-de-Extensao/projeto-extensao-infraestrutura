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
| `lambda.tf` | Ingestão Bronze, transformação Silver, IAM, agendas e triggers |
| `tests/` | Testes unitários das transformações Silver (`pytest`) |
| `lambda_src/` | Handlers Python das funções Lambda |
| `lambda-requirements.txt` | Dependências empacotadas na Lambda Layer |
| `outputs.tf` | URLs de acesso, DNS do ALB, Swagger, IPs e comandos SSH |
| `terraform.tfvars.example` | Exemplo de sobrescrita de variáveis |

## Como Executar

1. Configurar as credenciais da AWS no terminal (`aws configure` ou variaveis de ambiente).

  No AWS Academy, a role existente `LabRole` é usada pelas funções. A role precisa permitir
  operações S3 nos buckets Bronze/Silver, DynamoDB para o lock do `alteracoes.csv` e escrita de logs
  CloudWatch — a `LabRole` já cobre isso pelas `VocLabPolicy` anexadas a ela.

  A conta do Learner Lab **nega `iam:PutRolePolicy`**, então a política inline
  `arandu-fatores-lambda-access` não é criada por padrão (`manage_lambda_role_policy = false`).
  Com ela ligada, o apply falha com `AccessDenied` ao anexar a política e leva junto as 4 Lambdas,
  os log groups, as regras do EventBridge e a notificação do S3, que dependem dela.

  Numa conta própria, onde `lambda_execution_role_name` aponta para uma role dedicada que ainda
  não tem esses acessos, ative a política:

```bash
terraform apply -var='manage_lambda_role_policy=true'
```

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

O Terraform empacota o código Python e instala `xlrd` e `pymysql` na layer usando o executável configurado em
`lambda_build_python` (padrão `python`). Em ambientes Windows, informe o caminho do Python com
`-var='lambda_build_python=C:/Python312/python.exe'` se `python` não estiver no PATH.

As Lambdas de ingestão são agendadas mensalmente para INMET e ANBIMA e semanalmente para
MusicBrainz e para as chamadas do clube (domingo, depois da reunião de sábado). A Silver roda por
notificação `s3:ObjectCreated` nos prefixes `clima/`, `eventos/`, `feriados/` e `chamadas/`. Os
objetos originais e `alteracoes.csv` ficam no bucket Bronze; as saídas são `clima_horario.csv.gz`,
`eventos_cidade.csv.gz`, `feriados_nacionais.csv.gz` e `presenca_chamadas.csv.gz` no bucket Silver.

A `arandu-fatores-chamadas` é a única Lambda dentro da VPC: roda na subnet privada do backend, com
o SG `arandu-sg-lambda-banco`, liberado na porta 3306 do RDS, e sai para S3 e DynamoDB pelo NAT.
Ela exporta só `id_chamada`, `data_chamada` e `presenca`, sem nenhum dado pessoal do desbravador,
e grava um arquivo novo apenas quando o conteúdo muda.
Os logs ficam em `/aws/lambda/arandu-fatores-*` no CloudWatch, com retenção de 14 dias.

O dump MusicBrainz é baixado em streaming multipart para o S3, sem arquivo local. A Silver também
faz leitura sequencial do tar.xz e registra duração e pico de RSS nos logs. Seu timeout e memória
estão nos limites máximos da Lambda (900 segundos e 10.240 MB); valide uma execução completa do
dump na conta AWS. Se atingir timeout/memória, a próxima etapa é particionar/pré-filtrar fora da
Lambda, por exemplo com ECS/Fargate ou AWS Batch. O runtime AWS ainda não foi medido com o dump real.

Como referência, o dump `20260926-001002/event.tar.xz` (49.483.012 bytes) foi processado no host
Windows em 4,51 s, gerando 235 linhas para São Paulo; a amostragem do processo apontou pico de RSS
de 45,07 MiB. A transferência HTTP levou 41,28 s. Esses números locais não substituem o primeiro
teste na Lambda: confirme duração e `Max Memory Used` no registro `REPORT` do CloudWatch.

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
