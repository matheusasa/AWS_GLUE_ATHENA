# airflow — Orquestração com Apache Airflow (DAG)

Este diretório contém o **DAG** que orquestra os jobs Glue (Bronze → Prata →
Ouro) via Apache Airflow — seja rodando no **Amazon MWAA** (gerenciado) ou
**localmente** para desenvolvimento.

```
airflow/
├── dags/
│   └── medalhao_dag.py     # DAG: bronze -> silver -> gold (AwsGlueJobOperator)
└── requirements.txt        # apache-airflow-providers-amazon
```

## O que o DAG faz

- 3 tarefas, uma por job Glue, com `wait_for_completion=True` (síncrono).
- Dependência: `bronze >> silver >> gold` (só avança na ordem certa).
- `retries=1`, `catchup=False`, `max_active_runs=1` (sem concorrência).

## Opção A — Amazon MWAA (produção)

1. Provisione o ambiente MWAA via Terraform (módulo `terraform/modules/mwaa`,
   **opcional** e mais caro — leia o README do módulo).
2. Faça upload dos arquivos para o bucket de DAGs:

```bash
BUCKET=$(terraform -chdir=terraform/envs/dev output -raw mwaa_dags_bucket 2>/dev/null)
aws s3 cp dags/medalhao_dag.py s3://$BUCKET/dags/medalhao_dag.py
aws s3 cp requirements.txt      s3://$BUCKET/requirements.txt
```

3. No console do MWAA, aguarde a sincronização e abra a UI do Airflow.
4. Os nomes dos jobs vêm das variáveis de ambiente (`GLUE_JOB_*`) configuradas
   pelo módulo MWAA, ou dos defaults no topo do DAG.

## Opção B — Airflow local (desenvolvimento)

```bash
# Use a imagem oficial com providers já incluídos
docker run -d --name airflow \
  -p 8080:8080 \
  -v "$PWD/dags:/usr/local/airflow/dags" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=false \
  -e AWS_DEFAULT_REGION=sa-east-1 \
  apache/airflow:2.10.3-python3.11 standalone

# UI em http://localhost:8080 (user/senha: admin/admin)
```

Alternativa com `pip` (mais leve, só para validar a DAG):

```bash
pip install "apache-airflow==2.10.3" apache-airflow-providers-amazon
export AIRFLOW_HOME=$PWD/.airflow
airflow db migrate
airflow standalone
```

> Localmente, as tasks só rodam de verdade se houver credenciais AWS
> (`aws configure`) e os jobs Glue existirem. Para validar só a topologia da
> DAG, use `airflow dags test pipeline_medalhao 2026-07-01` (mock).

## Diferença vs Step Functions

O Step Functions orquestra dentro da AWS (sem servidor extra); o Airflow dá
mais controle (Python, sensores, XCom, backfill, dependências complexas e
multi-cloud) mas exige manter uma plataforma. Veja `docs/12-orquestracao-airflow.md`.
