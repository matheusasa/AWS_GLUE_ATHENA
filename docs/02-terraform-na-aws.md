# Módulo 02 — Terraform na AWS

## Objetivos

Configurar o **provider AWS**, entender as formas de **autenticação**, provisionar recursos reais (S3, IAM) e organizar o **estado remoto** de forma segura.

---

## 1. Pré-requisitos

- Conta AWS (use IAM Identity Center ou um usuário com chaves de acesso para estudo).
- **AWS CLI v2** instalado e configurado: `aws configure` (pede Access Key, Secret Key, região, output).
- Terraform instalado (Módulo 01).

```bash
aws sts get-caller-identity   # confirma quem você é na AWS
```

---

## 2. O provider AWS

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# provider.tf
provider "aws" {
  region = "sa-east-1"   # São Paulo; ajuste conforme sua região

  # Tags padrão aplicadas em TODOS os recursos criados por este provider.
  default_tags {
    tags = {
      Projeto    = "datalake-treinamento"
      Gerenciado = "terraform"
    }
  }
}
```

> **default_tags** (provider v5+) é a forma mais limpa de garantir tagging. Os recursos ainda podem ter tags próprias que se somam às padrão.

### Autenticação (como o Terraconsegue se logar?)

O provider procura credenciais nesta ordem:

1. Variáveis de ambiente (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
2. `~/.aws/credentials` (criado pelo `aws configure`) — **mais comum para estudo**.
3. **Profiles** nomeados: `aws configure --profile dev` e no Terraform `provider "aws" { profile = "dev" }`.
4. **IAM Role** assumida via `assume_role` (muito usado em CI/CD ou cross-account).
5. Credenciais do ambiente (EC2/ECS IMDS, IRSA no EKS).

**Boa prática em time:** use **IAM Identity Center (SSO)** com `aws sso login` e profiles por conta. Em **CI/CD**, use **OIDC** (sem chaves de longa duração no pipeline).

---

## 3. Provisionando recursos: S3 e IAM

### 3.1 Bucket S3 (o coração do data lake)

```hcl
# s3.tf
resource "aws_s3_bucket" "dados" {
  bucket = "meu-datalake-treinamento-${var.ambiente}"  # nome é GLOBAL na AWS

  tags = { Camada = "raw" }
}

# Versionamento (recuperação contra deleções acidentais)
resource "aws_s3_bucket_versioning" "dados" {
  bucket = aws_s3_bucket.dados.id
  versioning_configuration { status = "Enabled" }
}

# Criptografia em repouso (obrigatório em ambientes sérios)
resource "aws_s3_bucket_server_side_encryption_configuration" "dados" {
  bucket = aws_s3_bucket.dados.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Bloquear acesso público (NUNCA exponha um data lake)
resource "aws_s3_bucket_public_access_block" "dados" {
  bucket                  = aws_s3_bucket.dados.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

Note como **um único bucket** vira **quatro recursos**: `aws_s3_bucket` + `_versioning` + `_server_side_encryption_configuration` + `_public_access_block`. Esse padrão "recurso separado por atributo" é típico do provider AWS v4/v5 e deixa o código mais modular.

### 3.2 IAM: role para o Glue

O Glue precisa de uma **role** com permissões para ler/gravar no S3 e usar o Catálogo. Por enquanto, a construção básica:

```hcl
# iam.tf (forma didática; no projeto usamos o módulo iam_glue_role)
data "aws_iam_policy_document" "assume_glue" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.ambiente}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.assume_glue.json
}

# AWS já tem uma managed policy com as permissões básicas de Glue/S3/CloudWatch
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}
```

---

## 4. Estado remoto: S3 + DynamoDB (lock)

Rodar Terraform em time com state local **vira caos**. A solução é um **backend remoto**. Para a AWS, o padrão é **S3** (guarda o state) + **DynamoDB** (faz *lock*, impedindo dois `apply` simultâneos).

### Passo 1 — crie o "bucket de estado" UMA vez (manualmente ou por código separado)

```bash
# Este bucket guarda o state de TODOS os outros projetos. Crie 1x.
aws s3api create-bucket \
  --bucket tf-state-meu-datalake-123 \
  --region sa-east-1 \
  --create-bucket-configuration LocationConstraint=sa-east-1

aws s3api put-bucket-versioning --bucket tf-state-meu-datalake-123 \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket tf-state-meu-datalake-123 \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Tabela de lock
aws dynamodb create-table \
  --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region sa-east-1
```

### Passo 2 — configure o backend no seu projeto

```hcl
# backend.tf (deve estar vazio de state quando você rodar 'terraform init' pela 1ª vez)
terraform {
  backend "s3" {
    bucket         = "tf-state-meu-datalake-123"
    key            = "datalake/dev/terraform.tfstate"   # caminho do "arquivo" no S3
    region         = "sa-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
  }
}
```

Rode `terraform init` (ele oferece `migrate state` se já existir um state local). A partir daqui, o `terraform.tfstate` vive no S3 e o lock impede corridas.

> ⚠️ O **bucket de state é uma "galinha dos ovos de ouro"**: ele próprio **não** deve ser gerenciado pelo backend que ele hospeda. Crie-o de forma isolada.

---

## 5. `data sources`: consumindo o que já existe

Para referenciar recursos que **já existem** na conta (sem gerenciá-los):

```hcl
# Descobre a região atual (útil para montar ARNs)
data "aws_region" "atual" {}
data "aws_caller_identity" "atual" {}

#Conta atual: ${data.aws_caller_identity.atual.account_id}
#Região atual: ${data.aws_region.atual.name}
```

---

## 6. Importando recursos existentes

Se alguém criou um bucket no console e agora você quer gerenciá-lo no Terraform:

```bash
terraform import aws_s3_bucket.dados meu-datalake-treinamento-dev
```

Isso traz o recurso **para dentro do state**, mas **não gera o código**. Use `terraform plan` para ver a diferença entre o que existe e o que o código descreve, e ajuste o `.tf` até o plan ficar limpo. (Ferramentas como `terraformer` ou `aws terraform code` aceleram a geração.)

---

## 7. Custo e segurança: checklist

- Habilite **versionamento** e **criptografia** nos buckets.
- **Bloqueie acesso público** sempre.
- Use **tags** (projeto, ambiente, dono, custo) — sem tags não há controle financeiro.
- Prefira **roles/SSO** a chaves de longa duração.
- Em estudo: rode `terraform destroy` ao final para zerar custos.

---

## Exercícios do módulo

**Ex. 1 — Primeiro bucket:** Provisione um bucket S3 com versionamento, criptografia e bloqueio público (código acima). Rode `plan`/`apply`. Confirme no console. Depois `destroy`.

**Ex. 2 — Backend remoto:** Crie o bucket de estado e a tabela DynamoDB (Passo 1). Adicione o `backend.tf` (Passo 2), rode `init`. Rode `apply` de novo: veja que o `tfstate` agora está no S3 (`aws s3 ls` do objeto).

**Ex. 3 — data source:** Crie um `data "aws_region"` e use-o num output. Faça `terraform output` para imprimir a região.

**Ex. 4 — Import:** Crie um bucket pelo console. Use `terraform import` para trazê-lo ao state, e corrija o `.tf` até `plan` mostrar "No changes".

**Ex. 5 — Reflita:** Por que o bucket que guarda o **state** não deve ser criado pelo **mesmo** Terraform que ele armazena? ¹

¹ *Porque seria uma dependência circular: o Terraform precisaria do backend (S3) para guardar o state que descreve a criação do próprio backend. O "bucket de estado" é criado isoladamente, uma única vez.*
