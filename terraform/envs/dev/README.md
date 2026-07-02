# Ambiente DEV

Provisiona um Data Lake completo (medalhão Bronze/Prata/Ouro) para estudo.

## Pré-requisitos (uma única vez)

1. **Bucket de estado + tabela de lock** — crie antes de rodar o `init`:

```bash
BUCKET=tf-state-treinamento-123   # use um nome GLOBAL único
aws s3api create-bucket --bucket $BUCKET --region sa-east-1 \
  --create-bucket-configuration LocationConstraint=sa-east-1
aws s3api put-bucket-versioning --bucket $BUCKET \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket $BUCKET \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region sa-east-1
```

2. Edite `backend.tf` (dentro do bloco `terraform` em `main.tf`) trocando o
   `bucket` pelo nome que você criou.

## Como aplicar

```bash
cp terraform.tfvars.example terraform.tfvars
# edite terraform.tfvars -> sufixo_unico (algo único seu)

terraform init
terraform plan
terraform apply
```

## Após aplicar

1. Suba os dados de exemplo para a landing:

```bash
DEV_BUCKET=$(terraform output -raw buckets | grep bronze || terraform output -json buckets | jq -r .bronze)
aws s3 cp ../../../data/sample/vendas.csv   s3://$DEV_BUCKET/landing/vendas/dt=2026-07-01/
aws s3 cp ../../../data/sample/clientes.csv s3://$DEV_BUCKET/landing/clientes/dt=2026-07-01/
aws s3 cp ../../../data/sample/produtos.csv s3://$DEV_BUCKET/landing/produtos/dt=2026-07-01/
```

2. Rode os jobs pela ordem: **bronze_ingest → silver_transform → gold_aggregate**.
3. Rode os crawlers (ou aguarde o schedule) para popular as tabelas.
4. No **Athena**, selecione o workgroup de dev e consulte.

## Destruir (zera custos)

```bash
# Esvazie os buckets antes (o Terraform não deleta buckets não-vazios):
aws s3 rm s3://$DEV_BUCKET --recursive
# depois:
terraform destroy
```
