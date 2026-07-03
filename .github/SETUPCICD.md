# CI/CD — GitHub Actions

Dois pipelines:

| Workflow | O que faz | Quando roda |
|---|---|---|
| `terraform-ci.yml` | `fmt-check` + `validate` + `plan` (dev); `apply` em dev no merge; `apply` em prod manual | PR → plano; push main → apply dev; dispatch → apply prod |
| `python-ci.yml` | `py_compile` + `flake8` + **smoke test** do gerador Faker + valida o JSON do ASL | PR e push que mexam em `.py` |

Veja também o módulo `docs/13-cicd-github-actions.md`.

---

## Setup (uma única vez)

### 1) OIDC: confiar no GitHub na AWS (sem chaves estáticas)

Crie um **Identity Provider OIDC** na AWS (IAM → Identity providers → Add provider):

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

### 2) IAM Role para o CI (uma por ambiente: dev/prod)

Trust policy da role de **dev** (limitando ao seu repo e ao workflow `terraform-ci.yml`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<CONTA>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:matheusasa/AWS_GLUE_ATHENA:ref:refs/heads/main"
      }
    }
  }]
}
```

> Para permitir PRs de qualquer branch, use `StringLike` com `repo:matheusasa/AWS_GLUE_ATHENA:*`.
> Anexe a essa role uma policy com as permissões que o Terraform precisa (S3, Glue, IAM,
> Athena, Step Functions, CloudWatch, etc.) — ou use uma gerenciada ampla para estudo.

### 3) Secrets do repositório (Settings → Secrets and variables → Actions)

| Secret | Valor |
|---|---|
| `AWS_ROLE_TO_ASSUME_DEV` | ARN da role de dev |
| `AWS_ROLE_TO_ASSUME_PROD` | ARN da role de prod (só se for usar apply manual de prod) |
| `TF_VAR_sufixo_unico` | Seu sufixo único (mesmo do `terraform.tfvars`) |

### 4) Environments (para o apply)

- Settings → Environments → crie `dev` e `prod`.
- Em `prod`, ative **Required reviewers** (aprovação manual antes do apply).

### 5) Backend

O bucket S3 de estado + tabela DynamoDB de lock já devem existir
(`terraform/envs/dev/README.md`). O CI roda `terraform init` que usa esse backend.

---

## Como testar localmente (antes de abrir PR)

```bash
# Equivalente ao CI de Terraform
terraform fmt -check -recursive terraform/
terraform -chdir=terraform/envs/dev init
terraform -chdir=terraform/envs/dev validate
terraform -chdir=terraform/envs/dev plan

# Equivalente ao CI de Python
find glue-jobs airflow data/sample -name '*.py' | xargs -n1 python -m py_compile
flake8 glue-jobs airflow data/sample --select=E9,F63,F7,F82
python data/sample/generate_data.py --vendas 50 --dirty 0.05 --with-pii --outdir /tmp/gen
```

---

## Boas práticas aplicadas

- **OIDC** em vez de chaves de longa duração (Access Key) no pipeline.
- **Menor privilégio:** role só com o necessário; condition `sub` limita repo/branch.
- **Gates:** PR só faz `plan`; `apply` em dev exige merge; `apply` em prod exige aprovação.
- **Artefato:** o plano é salvo (`upload-artifact`) e mostrado no **Step Summary**.
- **Falha rápida:** `fmt-check` e `validate` rodam antes do `plan`.
