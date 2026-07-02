# Terraform — Data Lake AWS (medalhão)

Infraestrutura como código que provisiona, com um `terraform apply`:

- **3 buckets S3** (Bronze / Prata / Ouro) com versionamento, criptografia,
  bloqueio de acesso público e lifecycle.
- **Role IAM** least-privilege para o Glue (só acessa os buckets do lake).
- **3 bancos no Glue Data Catalog** + crawlers para descobrir schema.
- **3 jobs Glue** (bronze_ingest, silver_transform, gold_aggregate) com
  scripts PySpark versionados e enviados ao S3 automaticamente.
- **Athena** workgroup para consulta SQL.

## Estrutura

```
terraform/
├── modules/                      # Módulos reutilizáveis (a "biblioteca")
│   ├── s3_data_lake/             # Buckets por camada (for_each)
│   ├── iam_glue_role/            # Role + políticas least-privilege
│   ├── glue_catalog_database/    # Banco do Catálogo + crawlers
│   ├── glue_job/                 # Jobs PySpark (mapa de jobs)
│   ├── athena_workgroup/         # Workgroup Athena com limite de custo
│   ├── step_function_pipeline/   # ORQUESTRAÇÃO: State Machine bronze->prata->ouro
│   └── mwaa/                     # ORQUESTRAÇÃO: Airflow gerenciado (opcional, $)
└── envs/
    ├── dev/                      # Ambiente de estudo (mais barato)
    └── prod/                     # Ambiente de produção (mais recursos)
```

> **Orquestração:** o `step_function_pipeline` já vem ligado em dev e prod
> (em dev, sem agendamento; em prod, agendado diariamente). O `mwaa` é
> **opcional** (custo por hora) — veja `docs/12-orquestracao-airflow.md`.

## Por que módulos?

Os módulos encapsulam recursos e expõem uma interface (variáveis/outputs),
como funções. Assim, `dev` e `prod` chamam os **mesmos** módulos mudando só
parâmetros — sem duplicar lógica (princípio DRY). Veja `docs/08-terraform-modulos-ambientes.md`.

## Fluxo padrão

```bash
cd envs/dev
cp terraform.tfvars.example terraform.tfvars   # ajuste o sufixo_unico
terraform init
terraform plan                                  # LEIA o plano
terraform apply
```

Destruir (em dev, libera custos):

```bash
# Esvazie os buckets antes (Terraform não remove bucket não-vazio):
aws s3 rm s3://<bucket-bronze> --recursive
terraform destroy
```

## Pontos de atenção

- **Backend remoto:** o bloco `backend "s3"` em cada `envs/*/main.tf` aponta
  para um bucket de estado que você deve criar **uma vez**, manualmente
  (instruções em `envs/dev/README.md`). O bucket de estado não pode ser
  gerenciado pelo próprio Terraform que ele hospeda.
- **`sufixo_unico`:** nomes de bucket são globais; esse sufixo evita colisão.
- **Custos:** tudo aqui gera cobrança. Use `dev`, monitore no Cost Explorer e
  rode `terraform destroy` ao terminar.
- **Não versione `terraform.tfvars`** (pode ter particularidades); versione
  apenas o `.tfvars.example`.

## Ordem recomendada de estudo

1. `modules/s3_data_lake` → `docs/02` (recursos, for_each, atributos separados).
2. `modules/iam_glue_role` → `docs/09` (least privilege, políticas).
3. `modules/glue_catalog_database` → `docs/03` (Catálogo, crawlers).
4. `modules/glue_job` → `docs/04` (jobs, argumentos).
5. `envs/dev` → `docs/08` (juntando tudo; módulos + ambientes).
