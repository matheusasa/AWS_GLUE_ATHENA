# Treinamento: Terraform + Solução de Dados na AWS (Glue + PySpark + Medalhão)

Treinamento progressivo (do básico ao avançado) que combina **Infraestrutura como Código com Terraform**, a **stack de dados da AWS** e o uso de **AWS Glue com PySpark** para construir um **Data Lake na Arquitetura Medalhão** (Bronze → Prata → Ouro).

O material equilibra teoria e prática: cada módulo explica os conceitos e termina com exercícios, e há uma pasta de código totalmente funcional (Terraform + scripts Glue/PySpark + dados de exemplo) para você rodar de verdade.

---

## Para quem é

- Pessoas engenheiras de dados, DevOps/SRE e desenvolvedoras que querem dominar **dados na AWS com infraestrutura reproduzível**.
- Trilha **progressiva**: começa do zero (o que é IaC, o que é Terraform, primeiros recursos) e chega a tópicos avançados (módulos reutilizáveis, workspaces, CI/CD, otimização de Spark, governança).
- Pré-requisitos básicos: familiaridade com linha de comando, SQL e Python. O resto o treinamento cobre.

---

## Estrutura do projeto

```
treinamento-terraform-aws-glue/
├── docs/                       # Material de estudo (Markdown), módulo por módulo
│   ├── 01-fundamentos-terraform.md
│   ├── 02-terraform-na-aws.md
│   ├── 03-servicos-dados-aws.md
│   ├── 04-glue-pyspark-fundamentos.md
│   ├── 05-glue-pyspark-intermediario.md
│   ├── 06-glue-pyspark-avancado.md
│   ├── 07-arquitetura-medalhao.md
│   ├── 08-terraform-modulos-ambientes.md
│   ├── 09-governanca-boas-praticas.md
│   ├── 10-laboratorios-exercicios.md
│   ├── 11-orquestracao-step-functions.md
│   ├── 12-orquestracao-airflow.md
│   └── 13-cicd-github-actions.md
├── .github/                    # CI/CD com GitHub Actions (workflows + README)
│   └── workflows/
│       ├── terraform-ci.yml    # fmt/validate/plan/apply (OIDC, gates dev/prod)
│       └── python-ci.yml       # py_compile + flake8 + smoke test (Faker)
├── terraform/                  # Infraestrutura como código (funcional)
│   ├── modules/                # Módulos reutilizáveis
│   │   ├── s3_data_lake/
│   │   ├── glue_catalog_database/
│   │   ├── glue_job/
│   │   ├── iam_glue_role/
│   │   ├── athena_workgroup/
│   │   ├── step_function_pipeline/   # orquestração (Step Functions)
│   │   └── mwaa/                     # orquestração (Airflow gerenciado)
│   └── envs/                   # Ambientes dev e prod
│       ├── dev/
│       └── prod/
├── glue-jobs/                  # Scripts PySpark para AWS Glue
│   ├── bronze_ingest.py
│   ├── silver_transform.py
│   ├── gold_aggregate.py
│   └── common/glue_utils.py
├── airflow/                    # DAG Apache Airflow (orquestração)
│   ├── dags/medalhao_dag.py
│   └── requirements.txt
├── data/sample/               # Dados de exemplo (+ gerador com Faker)
└── Makefile                    # Atalhos úteis (validar Terraform, etc.)
```

---

## Trilha de estudo sugerida

1. **`docs/01-fundamentos-terraform.md`** — O que é IaC, instalação, ciclo de vida (`init/plan/apply/destroy`), variáveis, state.
2. **`docs/02-terraform-na-aws.md`** — Provider AWS, autenticação, provisionando S3, IAM e Glue.
3. **`docs/03-servicos-dados-aws.md`** — Visão geral do stack: S3, Glue, Athena, Lake Formation, Redshift, Kinesis, QuickSight.
4. **`docs/04-glue-pyspark-fundamentos.md`** — Arquitetura do Glue, DynamicFrames, primeiro job PySpark.
5. **`docs/05-glue-pyspark-intermediario.md`** — Transformações, joins, particionamento, Catálogo.
6. **`docs/06-glue-pyspark-avancado.md`** — Performance, bookmarks, UDFs, formatos (Parquet/Iceberg), incremental.
7. **`docs/07-arquitetura-medalhao.md`** — Camadas Bronze/Prata/Ouro e padrões de cada uma.
8. **`docs/08-terraform-modulos-ambientes.md`** — Módulos, `terraform workspace`, múltiplos ambientes, CI/CD.
9. **`docs/09-governanca-boas-praticas.md`** — Lake Formation, segurança, custo, tagging.
10. **`docs/10-laboratorios-exercicios.md`** — Laboratórios práticos guiados com soluções.
11. **`docs/11-orquestracao-step-functions.md`** — Orquestração com AWS Step Functions (`.sync`, Retry/Catch, agendamento).
12. **`docs/12-orquestracao-airflow.md`** — Orquestração com Apache Airflow (MWAA, DAG, `AwsGlueJobOperator`, backfill).
13. **`docs/13-cicd-github-actions.md`** — CI/CD com GitHub Actions (OIDC, gates dev/prod, pipelines do projeto).

---

## Como usar

1. Instale o **Terraform** (≥ 1.5) e a **AWS CLI** (v2), configure `aws configure`.
2. Leia os módulos em ordem. Vá rodando os exemplos da pasta `terraform/`.
3. Para os laboratórios de Glue/PySpark, suba a infra com Terraform (módulos `glue_job`, `s3_data_lake`) e execute os jobs da pasta `glue-jobs/`.
4. Use o **`Makefile`** para os comandos mais comuns (`make tf-fmt`, `make tf-plan-dev`, etc.).

> ⚠️ **Custos:** Os recursos criados (Glue, S3, Athena) geram cobranças na AWS. Use sempre a conta de `dev`, destrua com `terraform destroy` ao terminar e confira o [calculator da AWS](https://calculator.aws). Recomendamos o **Free Tier** e evitar dados sensíveis em ambientes de estudo.

---

## O que você vai 