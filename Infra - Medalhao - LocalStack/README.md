# Arquitetura Medalhao com LocalStack

Provisionamento local dos buckets S3 das camadas Bronze, Silver e Gold utilizando LocalStack e Terraform.

## Estrutura de Arquivos

- `docker-compose.yml`: container do LocalStack
- `.env`: configuracao do token de autenticacao do LocalStack
- `providers.tf`: provider AWS apontando para http://localhost:4566
- `variables.tf`: definicoes de variaveis dos buckets
- `s3_medallion.tf`: declaracao dos buckets S3 (Bronze, Silver, Gold e Documentos)
- `outputs.tf`: outputs com os nomes dos buckets criados

## Execucao

1. Subir o LocalStack:
```bash
docker compose up -d
```

2. Aplicar o Terraform para criar os buckets:
```bash
terraform init
terraform apply -auto-approve
```

## Validacao via AWS CLI

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
```

## Destruir Recursos

```bash
terraform destroy -auto-approve
docker compose down -v
```
