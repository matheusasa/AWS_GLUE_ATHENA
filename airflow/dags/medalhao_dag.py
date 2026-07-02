"""
medalhao_dag.py
DAG Apache Airflow que ORQUESTA os 3 jobs Glue do data lake na ordem da
arquitetura medalhão: Bronze -> Prata -> Ouro.

Cada tarefa é um AwsGlueJobOperator: inicia o job e espera o término
(comportamento síncrono por padrão). As dependências (>>) garantem a ordem.
Se um job falha, o Airflow não dispara os seguintes e aplica retries.

Como usar no MWAA: suba este arquivo para s3://<bucket-mwaa>/dags/medalhao_dag.py
e o requirements.txt para s3://<bucket-mwaa>/requirements.txt.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.amazon.aws.operators.glue import AwsGlueJobOperator

# Os nomes dos jobs podem vir da variável de ambiente (setada pelo módulo MWAA)
# ou de Airflow Variables; aqui usamos defaults alinhados ao Terraform.
DEFAULT_JOBS = {
    "bronze": os.getenv("GLUE_JOB_BRONZE", "dev-treinamento-bronze_ingest"),
    "silver": os.getenv("GLUE_JOB_SILVER", "dev-treinamento-silver_transform"),
    "gold":   os.getenv("GLUE_JOB_GOLD",   "dev-treinamento-gold_aggregate"),
}

# Região usada pelas tasks Glue
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "sa-east-1")

default_args = {
    "owner": "dados",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
    "email_on_failure": False,
}

with DAG(
    dag_id="pipeline_medalhao",
    description="Bronze -> Prata -> Ouro via jobs AWS Glue",
    default_args=default_args,
    start_date=datetime(2026, 1, 1),
    schedule="@daily",        # diário; troque por None para trigger manual
    catchup=False,            # não roda backlog histórico
    max_active_runs=1,        # evita execuções concorrentes do mesmo pipeline
    tags=["datalake", "glue", "medalhao"],
) as dag:

    bronze = AwsGlueJobOperator(
        task_id="bronze_ingest",
        job_name=DEFAULT_JOBS["bronze"],
        region_name=AWS_REGION,
        wait_for_completion=True,   # síncrono: só avança quando o job termina
        verbose=True,
    )

    silver = AwsGlueJobOperator(
        task_id="silver_transform",
        job_name=DEFAULT_JOBS["silver"],
        region_name=AWS_REGION,
        wait_for_completion=True,
        verbose=True,
    )

    gold = AwsGlueJobOperator(
        task_id="gold_aggregate",
        job_name=DEFAULT_JOBS["gold"],
        region_name=AWS_REGION,
        wait_for_completion=True,
        verbose=True,
    )

    # Encadeamento: Bronze -> Prata -> Ouro
    bronze >> silver >> gold
