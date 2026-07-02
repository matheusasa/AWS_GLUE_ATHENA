# Módulo 01 — Fundamentos do Terraform

## Objetivos

Ao final deste módulo você deve entender o que é **Infraestrutura como Código (IaC)**, como o **Terraform** funciona, seu ciclo de vida, e ser capaz de provisionar um primeiro recurso na nuvem.

---

## 1. O que é Infraestrutura como Código (IaC)

IaC é o ato de **descrever sua infraestrutura em arquivos de texto versionáveis**, em vez de criá-la manualmente (clicando no console). As vantagens são:

- **Reprodutibilidade:** o mesmo código cria o mesmo ambiente em dev e prod.
- **Versionamento:** cada mudança de infra entra no Git, com histórico e revisão.
- **Velocidade:** criar/destruir dezenas de recursos leva segundos.
- **Consistência:** menos erro humano ("esqueci de abrir a porta X").
- **Documentação viva:** o código descreve o estado real.

Os principais concorrentes: **Terraform** (HashiCorp, declarativo, multi-cloud), **AWS CloudFormation** (nativo AWS, YAML/JSON), **Pulumi** (IaC em linguagens como Python/TS) e **CDK** (AWS, usa linguagens de programação).

### Declarativo vs. imperativo

O Terraform é **declarativo**: você descreve **o estado desejado** ("quero um bucket S3 chamado X") e a ferramenta descobre **como** chegar lá. Você não escreve "primeiro crie o bucket, depois aplique a policy..." — diz apenas o resultado.

---

## 2. Por que Terraform e não CloudFormation?

| Critério | Terraform | CloudFormation |
|---|---|---|
| Multi-cloud | ✅ (AWS, GCP, Azure, etc.) | ❌ só AWS |
| Linguagem | HCL (legível) | YAML/JSON (verboso) |
| Comunidade/módulos | Muito grande | Menor |
| Estado | Em arquivo (`tfstate`) | Gerenciado pela AWS |
| Curva de aprendizado | Suave | Média |

Para um time que trabalha **só na AWS**, ambos servem. Escolhemos Terraform aqui pela legibilidade, ecossistema de módulos e portabilidade de conhecimento.

---

## 3. Conceitos-chave

- **Provider:** o plugin que fala com uma API (AWS, GCP, Azure, GitHub...). Ex.: `aws`.
- **Resource:** um objeto a criar (bucket, role, job do Glue). É o bloco básico.
- **Data source:** lê algo que **já existe** (ex.: "me dê a AMI mais recente") sem gerenciá-lo.
- **Variable (`variable`):** entrada parametrizável do módulo.
- **Output:** valor exposto para quem chama o módulo (ex.: o nome do bucket criado).
- **State (`terraform.tfstate`):** arquivo que registra **o que o Terraform já criou**. É a "memória" — sem ele, o Terraform não sabe o que é seu. **Nunca** versionar com segredos.
- **Module:** pasta reutilizável com recursos relacionados (ex.: um módulo `s3_data_lake`).
- **Plan:** simulação do que será feito. **Apply:** executa de fato.

---

## 4. Instalação

### Linux (ex.: Ubuntu)

```bash
# 1) Adicione o repositório da HashiCorp
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# 2) Instale
sudo apt update && sudo apt install terraform -y
terraform -version
```

### macOS

```bash
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
```

### Windows

Baixe o binário em <https://developer.hashicorp.com/terraform/downloads> ou use `winget install Hashicorp.Terraform`.

> Instale também a **AWS CLI v2** (`aws --version`) e rode `aws configure` com suas credenciais.

---

## 5. O ciclo de vida: init → fmt → validate → plan → apply → destroy

Vamos criar o primeiro projeto. Crie uma pasta e um arquivo `main.tf`:

```hcl
# main.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Recurso do provider "random": gera um número aleatório.
# Bom para um primeiro teste que não gasta nada na nuvem.
resource "random_id" "exemplo" {
  byte_length = 8
}

output "id_aleatorio" {
  value = random_id.exemplo.hex
}
```

Agora rode a sequência mágica:

```bash
terraform init      # Baixa providers e prepara o diretório (rode 1x por projeto)
terraform fmt       # Formata o código (equivalente a um "prettier")
terraform validate  # Checa sintaxe e consistência
terraform plan      # MOSTRA o que será feito (não aplica nada)
terraform apply     # Aplica de fato (pede confirmação; use -auto-approve p/ pular)
terraform show      # Mostra o estado atual
terraform destroy   # DESTROI tudo que foi criado por este código
```

Entenda bem o **plan** antes de aplicar: ele lista recursos a **criar (`+`)**, **destruir (`-`)** e **modificar em-place (`~`)** ou **recriar (`-/+`)**. Em produção, sempre leia o plan.

---

## 6. Variáveis, locals e outputs

Parametrizar evita repetição e permite reaproveitar o mesmo código entre ambientes.

```hcl
# variables.tf
variable "ambiente" {
  description = "Nome do ambiente (dev, prod)"
  type        = string
  default     = "dev"
}

variable "tags_comuns" {
  description = "Tags aplicadas em todos os recursos"
  type        = map(string)
  default     = { projeto = "datalake", dono = "dados" }
}
```

Formas de passar valor para uma variável (ordem de precedência):

1. Flag: `terraform apply -var="ambiente=prod"`
2. Arquivo `.tfvars`: `terraform apply -var-file="prod.tfvars"`
3. Variável de ambiente: `TF_VAR_ambiente=prod`
4. Default (usado só se nenhuma acima existir)

```hcl
# outputs.tf
output "ambiente_em_uso" {
  value       = var.ambiente
  description = "Confirma qual ambiente foi provisionado."
}
```

```hcl
# Locais: valores calculados para reaproveitar dentro do módulo
locals {
  prefixo = "${var.ambiente}-meu-projeto"
  bucket  = "${local.prefixo}-raw"   # ex.: dev-meu-projeto-raw
}
```

---

## 7. O arquivo de estado (state)

O `terraform.tfstate` é um JSON que mapeia cada recurso do código para o objeto real na nuvem. Pontos críticos:

- **Nunca edite à mão** (a menos que saiba exatamente o que faz).
- **Guarde em local remoto e compartilhado** (S3 + DynamoDB para lock) — veremos no Módulo 02. Nunca versionem o state local em time.
- Pode conter dados sensíveis (senhas, se você os referenciar). Cuidado com acesso.
- Comandos úteis: `terraform state list`, `terraform state show <recurso>`, `terraform state mv`, `terraform state rm`.

---

## 8. Dependências e grafos

O Terraform monta um **grafo de dependências** e decide a ordem de criação. Ele infere dependências quando um recurso referencia outro:

```hcl
resource "aws_s3_bucket" "dados" {
  bucket = "meu-bucket-dados-123"
}

resource "aws_s3_object" "arquivo" {
  bucket = aws_s3_bucket.dados.id   # <-- dependência explícita
  key    = "leia-me.txt"
  source = "leia-me.txt"
}
```

Quando não há referência direta mas você precisa de uma ordem, use `depends_on`.

---

## Exercícios do módulo

**Ex. 1 — Primeiro plan:** Crie um projeto com o `main.tf` do `random_id`. Rode `init`, `plan` e `apply`. Veja o `terraform.tfstate` gerado. Depois `destroy`.

**Ex. 2 — Variável:** Adicione uma variável `byte_length` (default 4) e use-a no `random_id`. Mude o valor com `-var` e re-aplique. Observe no plan que o recurso será **recriado** (porque `random_id` não suporta update in-place).

**Ex. 3 — Output:** Crie um output que mostre o `id_aleatorio` em maiúsculas usando `upper()`. (Consulte funções em <https://developer.hashicorp.com/terraform/language/functions>.)

**Ex. 4 — Leitura:** Antes de seguir, responda: por que o `terraform.tfstate` não deve ser commitado no Git em projetos reais? (Resposta no rodapé.) ¹

¹ *Porque (a) pode conter segredos, (b) gera conflitos quando mais de uma pessoa roda `apply` ao mesmo tempo e (c) deve ser centralizado em backend remoto com lock — não versionado.*
