# Módulo 13 — CI/CD com GitHub Actions

> Foco: **automatizar** validação, plano e deploy da infraestrutura (Terraform) e
> lint/sintaxe dos scripts Python (Glue/DAG/gerador) a cada mudança no Git.

## Objetivos

Entender como levar o Data Lake a um fluxo **GitOps/CI-CD**: toda mudança passa
por validação automática antes de chegar à AWS. Abordamos gatilhos, OIDC (sem
chaves estáticas), gates de ambiente e o pipeline do projeto
(`.github/workflows/`).

---

## 1. Por que CI/CD para dados/infra

Sem CI/CD, alguém roda `terraform apply` no próprio notebook — sem revisão, sem
rastreio, com risco de ambiente dessincronizado. Com CI/CD:

- **Toda mudança é revisada** via PR, com o `terraform plan` visível.
- **Padrão enforced:** `fmt -check` e `validate` barram código mal formatado/inválido.
- **Auditoria:** quem, quando e o que foi aplicado fica no histórico do GitHub.
- **Segurança:** credenciais via **OIDC**, sem Access Keys no pipeline.
- **Promoção controlada:** dev (automático) → prod (com aprovação).

---

## 2. Anatomia de um workflow (YAML)

```yaml
name: Terraform CI
on:
  pull_request:
    branches: [main]
    paths: ["terraform/**"]
permissions:
  id-token: write        # OIDC
  contents: read
  pull-requests: write
jobs:
  plan-dev:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME_DEV }}
          aws-region: sa-east-1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform validate
      - run: terraform plan
```

Conceitos: **`on`** (gatilhos), **`jobs/steps`** (o que executa), **`uses`**
(actions prontas), **`secrets`** (valores sensíveis), **`permissions`**
(capacidades do `GITHUB_TOKEN`), **`environment`** (gate de aprovação).

---

## 3. Autenticação AWS via OIDC (sem chaves)

O modo **inseguro** seria criar uma Access Key e guardar nos secrets. O modo
**moderno** é **OIDC**: o GitHub obtém um token JWT assinado e a AWS confia nele
para assumir uma role — **nenhuma chave de longa duraão existe**.

Passos (detalhados em `.github/README.md`):

1. Criar **Identity Provider OIDC** do GitHub na AWS
   (`token.actions.githubusercontent.com`).
2. Criar uma **IAM Role** com trust policy limitando o `sub` ao seu repo/branch.
3. Guardar o **ARN da role** num secret (`AWS_ROLE_TO_ASSUME_DEV`).
4. Usar `aws-actions/configure-aws-credentials@v4` com `role-to-assume`.

A condition `StringLike` no `sub` é o que impede que **outros** repositórios
públicos consigam assumir sua role.

---

## 4. Os pipelines deste projeto

### `terraform-ci.yml`

```
PR ─────────────────────► [fmt-check] → [validate] → [plan dev] (publica no Step Summary)
push main ───────────────► [apply dev]   (deploy automatizado em dev)
workflow_dispatch ───────► [apply prod]  (manual, exige environment "prod" com revisores)
```

- O `plan` é gravado como **artefato** e exibido no **Job Summary** do GitHub.
- `apply-dev` depende de `plan-dev` (`needs:`) e só roda em push/dispatch.
- `apply-prod` exige o **environment** `prod` com **Required reviewers**.

### `python-ci.yml`

- `py_compile` de todos os `.py` (sintaxe).
- `flake8` com seleção de erros graves (E9, F63/F7/F82) — falha só no que importa.
- **Smoke test:** instala `faker` e roda o `generate_data.py`, checando que os
  CSVs saem não vazios.
- Valida o **JSON do template ASL** do Step Functions.

> Jobs Glue dependem de `awsglue.*` (só existe no Glue), então aqui validamos
> **sintaxe** e **lógica pura**. Para testar transformações, abstraia funções
> puras (sem `awsglue`) e teste com `pytest` + PySpark local.

---

## 5. Gates e ambientes (promoção dev → prod)

No GitHub (**Settings → Environments**):

- `dev`: sem proteção — o apply roda automático no merge.
- `prod`: **Required reviewers** + opcional **deployment branch** = `main`.

Assim, mesmo que alguém dispare `apply-prod`, um humano precisa aprovar antes
da AWS ser tocada. Combine com **`terraform plan -detailed-exitcode`** para
bloquear mudanças inesperadas.

---

## 6. Padrões recomendados

- **Um PR por mudança**, pequeno e revisável.
- **Comente o plan** no PR (use o Step Summary ou uma action como
  `jbouter/terraform-pr-comment`).
- **Não versione segredos:** backend keys, passwords → Secrets Manager / SSM.
- **Pin de actions** por SHA em prod (ex.: `@v4` vira `@<commit-sha>`) para
  mitigar supply-chain.
- **Notificações:** integre falhas com Slack/Teams (action `rtCamp/action-slack-notify`).
- **Custo:** o CI só faz `plan` no PR (não cria recurso); `apply` só no merge.

---

## Exercícios do módulo

**Ex. 1 — Rode localmente o equivalente ao CI:** replique os comandos do
`.github/README.md` (fmt/validate/plan + py_compile/flake8/smoke) no seu
terminal. Garanta que tudo passa antes de abrir PR.

**Ex. 2 — Configure o OIDC:** crie o provider OIDC e a role de dev na AWS, adicione
o secret `AWS_ROLE_TO_ASSUME_DEV` e abra um PR mudando uma tag no `terraform/`.
Veja o job `plan-dev` rodar e o plano aparecer no Step Summary.

**Ex. 3 — Step Summary:** o workflow já publica o plano no `$GITHUB_STEP_SUMMARY`.
Abra um PR e confirme o plano renderizado na aba "Summary" da execução.

**Ex. 4 — Gate de prod:** configure o environment `prod` com **Required reviewers**
= você. Dispare `workflow_dispatch` e confirme que ele **fica aguardando aprovação**
antes do `apply`.

**Ex. 5 — Smoke test roubusto:** adicione ao `python-ci.yml` um passo que valida
que o `vendas.csv` gerado tem o **cabeçalho correto** e que existe pelo menos uma
linha com `id_venda` duplicado quando `--dirty > 0` (usando `csv.DictReader`).

**Ex. 6 — Pin por SHA (segurança):** substitua as actions `@v4`/`@v3` pelos SHAs
das releases (consulte o changelog de cada action). Justifique por que isso
mitiga ataques de supply-chain. ¹

**Ex. 7 — Plan no comentário do PR:** integre uma action (ex.:
`yunus-center/terraform-cloud-pr-comment` ou `jbouter`) para postar o plano como
comentário no PR, além do Step Summary.

¹ *Porque `@v4` é uma tag móvel — o mantenedor pode (se comprometido) repontá-la
para código malicioso, e seu pipeline passaria a rodá-lo. Pin por SHA imutável
garante que o código executado é exatamente o da release auditada.*
