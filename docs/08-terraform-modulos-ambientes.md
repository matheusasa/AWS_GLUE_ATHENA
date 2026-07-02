# Módulo 08 — Módulos, Ambientes e CI/CD

## Objetivos

Aprender a estruturar o Terraform com **módulos reutilizáveis**, gerenciar **múltiplos ambientes** (dev/prod) e integrar tudo num pipeline de **CI/CD**.

---

## 1. Por que módulos?

Repetir o mesmo bloco de S3/IAM/Glue em cada ambiente gera duplicação. Um **módulo** é uma pasta com recursos relacionados e uma **interface** (variáveis de entrada + outputs), exatamente como uma função em programação.

Benefícios:

- **Reúso:** o mesmo módulo `s3_data_lake` cria o lake em dev e prod mudando só parâmetros.
- **Abstração:** quem chama o módulo não precisa saber os detalhes internos.
- **Padronização:** o time inteiro cria buckets "do jeito certo".

### Anatomia de um módulo

```
modules/s3_data_lake/
├── main.tf         # os recursos
├── variables.tf    # entradas (com type, description, default)
├── outputs.tf      # saídas
└── README.md       # documenta como usar
```

Exemplo (veja a pasta `terraform/modules/` do projeto):

```hcl
# modules/s3_data_lake/variables.tf
variable "nome_base" { type = string }
variable "ambiente"  { type = string }
variable "camadas"   { type = list(string), default = ["bronze", "prata", "ouro"] }
```

```hcl
# modules/s3_data_lake/main.tf (trecho)
resource "aws_s3_bucket" "this" {
  for_each = toset(var.camadas)
  bucket   = "${var.ambiente}-${var.nome_base}-${each.key}"
}
```

```hcl
# modules/s3_data_lake/outputs.tf
output "buckets" {
  value = { for k, b in aws_s3_bucket.this : k => b.id }
}
```

### Usando o módulo

```hcl
# envs/dev/main.tf
module "data_lake" {
  source      = "../../modules/s3_data_lake"
  nome_base   = "treinamento"
  ambiente    = "dev"
  camadas     = ["bronze", "prata", "ouro"]
}
```

Rode `terraform init` para baixar o módulo local. Outputs do módulo são acessados assim: `module.data_lake.buckets["bronze"]`.

> **Dica de versionamento:** módulos podem morar em um repositório Git separado e ser referenciados por tag: `source = "git::https://.../infra-modules.git//s3_data_lake?ref=v1.2.0"`. Assim você tem versionamento semântico e revert fácil.

---

## 2. Estratégias para múltiplos ambientes

Existem três abordagens comuns. Cada uma tem prós e contras.

### 2.1 Diretórios por ambiente (recomendado para times)

```
terraform/envs/
├── dev/        main.tf, variables.tf, dev.tfvars, backend.tf (key=.../dev/...)
└── prod/       main.tf, variables.tf, prod.tfvars, backend.tf (key=.../prod/...)
```

Cada ambiente tem **seu próprio state** (no S3, em chaves diferentes) e seus próprios `tfvars`. O `main.tf` é quase idêntico entre eles; mudam apenas os valores.

- ✅ Isolamento total de state, fácil de entender, fácil de destruir o dev sem risco ao prod.
- ❌ Pequena duplicação entre os `main.tf` (mitigada pelos módulos compartilhados).

**É a estratégia que usamos neste projeto** (`terraform/envs/dev` e `terraform/envs/prod`).

### 2.2 Workspaces

```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
terraform apply -var-file=dev.tfvars
```

O `terraform.tfstate` é separado por workspace dentro do mesmo backend.

- ✅ Sem duplicar código; ótimo para muitos ambientes idênticos.
- ❌ State "escondido" (precisa lembrar em qual workspace está). Perigoso em prod. **Evite usar workspace para separar dev de prod em ambientes críticos.**

### 2.3 Terragrunt

Ferramenta externa que mantém configs **DRY** (sem repetição). Útil em organizações grandes. Fora do escopo deste treinamento, mas vale conhecer.

---

## 3. Convenções de nomes (evite dores de cabeça)

- Buckets S3 são **globalmente únicos** → inclua algo como `ambiente-projeto-camada-sufixoúnico`.
- Não use segredos em `.tfvars` → use AWS Secrets Manager / SSM Parameter Store e referencie via `data`.
- Mantenha `variables.tf` (declaração) separado de `terraform.tfvars` (valores reais). Versione apenas o `.tfvars.example`.
- **Backend é por ambiente** (`key = "datalake/dev/terraform.tfstate"`).

---

## 4. CI/CD com Terraform

Um pipeline típico (GitHub Actions, GitLab CI, AWS CodePipeline):

1. **PR aberto:** roda `terraform fmt -check`, `validate`, `tflint`/`tfsec` e `plan` (comenta o plan no PR).
2. **Merge na main:** roda `apply` para o ambiente dev.
3. **Promoção:** após aprovação, aplica em prod (com aprovação manual).

### Exemplo: GitHub Actions

```yaml
# .github/workflows/terraform.yml
name: Terraform
on:
  pull_request:
    paths: ["terraform/**"]
  workflow_dispatch:

permissions:
  id-token: write      # para OIDC
  contents: read
  pull-requests: write # para comentar o plan

jobs:
  plan-dev:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: terraform/envs/dev } }
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111122223333:role/gh-actions-tf   # OIDC, sem chaves
          aws-region: sa-east-1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform fmt -check -recursive
      - run: terraform validate
      - run: terraform plan -no-color 2>&1 | tee plan.txt
      # (use actions para postar plan.txt como comentário no PR)
```

> **OIDC é o padrão moderno:** o pipeline assume uma role via OIDC — **nenhuma** chave de longa duração precisa existir. Configure `Trust policy` na role aceitando o `token.actions.githubusercontent.com`.

---

## 5. Fluxo de trabalho recomendado no dia a dia

1. Crie/altere módulos em `terraform/modules/`.
2. Nos `envs/`, altere apenas parâmetros.
3. Sempre: `fmt` → `validate` → `plan` (leia!) → `apply`.
4. Code review do plan antes de aplicar em prod.
5. Mantenha o **state remoto** e nunca mexa no `.tfstate` à mão.

---

## Exercícios do módulo

**Ex. 1 — Crie um módulo:** Transforme o bucket S3 do Módulo 02 num módulo `s3_simple` com variáveis `nome` e `ambiente`. Chame-o de `envs/dev/main.tf`.

**Ex. 2 — Dois ambientes:** Replique a configuração para `envs/prod`, mudando apenas `ambiente = "prod"` e a região (se quiser). Confirme que cada um tem seu próprio state no S3.

**Ex. 3 — Workspaces (apenas para entender):** Em um diretório de testes, crie workspaces `dev`/`prod` e veja como o state se separa. Em seguida, **migrar** de volta para a estratégia de diretórios e documente por quê.

**Ex. 4 — CI local:** Simule o pipeline localmente: `terraform fmt -check -recursive && terraform -chdir=terraform/envs/dev validate && terraform -chdir=terraform/envs/dev plan`.

**Ex. 5 — Pergunta de prova:** Por que separar dev e prod por **diretórios** é geralmente mais seguro que por **workspaces**? ¹

¹ *Porque com workspaces o risco de "estar no workspace errado" é alto (alguém roda `apply` em prod achando que está em dev), e o state é implícito. Com diretórios, o `key` do backend e a pasta deixam o ambiente **explícito**, exigindo uma ação deliberada para tocar em prod.*
