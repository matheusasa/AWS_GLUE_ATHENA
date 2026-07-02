# Módulo 12 — Orquestração com Apache Airflow (MWAA)

> Foco deste módulo: **orquestração**. Como coordenar os jobs Glue com Apache
> Airflow, seja no Amazon MWAA (gerenciado) ou local. Não trata das
> transformações em si (Módulos 04–07).

## Objetivos

Entender o que é o **Apache Airflow**, quando ele vale a pena frente ao Step
Functions, os conceitos (DAG, task, operator, scheduler) e como orquestrar os
jobs Glue com o `AwsGlueJobOperator`.

---

## 1. O que é o Apache Airflow

O **Airflow** é uma plataforma de orquestração de workflows **open-source**
criada em Python. Você descreve fluxos como código (DAGs em Python), e o
Airflow agenda, executa, monitora e retenta as tarefas.

Conceitos-chave:

- **DAG** (*Directed Acyclic Graph*): o fluxo — um grafo orientado acíclico de
  tarefas com dependências. Definido em Python (`airflow/dags/medalhao_dag.py`).
- **Task**: um nó do DAG; uma unidade de trabalho.
- **Operator**: o "verbo" de uma task. Ex.: `AwsGlueJobOperator` roda um job
  Glue; `BashOperator` roda um comando; `PythonOperator` roda uma função.
- **Scheduler**: processo que decide quando cada DAG/task roda.
- **Executor**: quem executa as tasks (LocalExecutor, CeleryExecutor, KubernetesExecutor).
- **XCom**: mecanismo de troca de pequenos dados entre tasks.

---

## 2. Quando escolher Airflow vs Step Functions

| Critério | Step Functions | Airflow |
|---|---|---|
| Modelo | Serverless AWS, JSON (ASL) | Plataforma a gerenciar (ou MWAA), Python |
| Controle | Limitado ao que a ASL oferece | Total: Python, lógica, sensores, branches ricos |
| Multi-cloud | Só AWS | Multi-cloud / qualquer destino |
| Backfill (reprocessar datas passadas) | Manual | Nativo e poderoso |
| Sensores (esperar um evento) | Difícil | Sim, com poke/async |
| Dependências complexas | Verboso em ASL | Natural em Python |
| Custo | Por transição de estado | MWAA por hora (+ workers); self-managed pelos recursos |
| Curva | Menor | Média/alta |

**Resumo:** Step Functions é ideal para fluxos **na AWS, serverless, estáveis**.
Airflow brilha quando você precisa de **lógica rica, backfill, sensores,
multi-destino** ou já tem expertise em Python — com o custo de operar a plataforma.

---

## 3. Amazon MWAA (versão gerenciada)

O **MWAA** é o Airflow gerenciado pela AWS: ela cuida do scheduler, webserver
e workers. Você só sobe os DAGs (em um bucket S3) e configura.

- DAGs vivem em `s3://<bucket>/dags/*.py`.
- Dependências Python em `s3://<bucket>/requirements.txt`.
- Plugins em `s3://<bucket>/plugins/`.
- Precisa de **VPC com 2 sub-redes em AZs distintas**.

> **Custo:** o MWAA cobra por hora enquanto o ambiente existe, mesmo sem uso.
> Use para aprender e **destrua** depois. Para só validar a DAG, rode localmente.

O módulo `terraform/modules/mwaa` provisiona o ambiente + bucket de DAGs +
role de execução (com permissões de Glue). É **opcional** (não vem ligado por
padrão no `envs/dev`).

---

## 4. O operador `AwsGlueJobOperator`

```python
from airflow.providers.amazon.aws.operators.glue import AwsGlueJobOperator

bronze = AwsGlueJobOperator(
    task_id="bronze_ingest",
    job_name="dev-treinamento-bronze_ingest",
    region_name="sa-east-1",
    wait_for_completion=True,   # síncrono: só avança quando o job termina
    verbose=True,
)
```

- `wait_for_completion=True` → a task fica `running` até o job terminar (como
  o `.sync` do Step Functions).
- Se o job falha, a task falha e o Airflow aplica os `retries` do `default_args`.

---

## 5. A DAG do projeto (`airflow/dags/medalhao_dag.py`)

```python
bronze = AwsGlueJobOperator(task_id="bronze_ingest",  job_name=..., wait_for_completion=True)
silver = AwsGlueJobOperator(task_id="silver_transform", job_name=..., wait_for_completion=True)
gold   = AwsGlueJobOperator(task_id="gold_aggregate",  job_name=..., wait_for_completion=True)

bronze >> silver >> gold          # dependências: ordem da medalhão
```

Configurações importantes:

- `schedule="@daily"` → dispara todo dia (cron). Use `None` para só manual.
- `catchup=False` → não tenta rodar o "backlog" desde `start_date`.
- `max_active_runs=1` → não roda duas instâncias do mesmo pipeline ao mesmo
  tempo (evita sobrescrever partições concorrentemente).
- `retries=1` com `retry_delay` → retenta falhas transitórias.

---

## 6. Dependências entre tasks (além da sequência simples)

```python
# Paralelo a partir de um ponto
bronze >> [silver_vendas, silver_estoque]
[silver_vendas, silver_estoque] >> gold

# Condicional (BranchPythonOperator)
check >> branch
branch >> [roda_silver, pula]

# Sensor: só avança quando um arquivo/partição existir
esperar_arquivo = S3KeySensor(
    task_id="espera_landing",
    bucket_name="meu-bucket",
    bucket_key="landing/vendas/dt={{ ds }}/*.csv",
    poke_interval=60,
)
esperar_arquivo >> bronze
```

Sensores são um **ponto forte** do Airflow: esperar um arquivo chegar, uma
partição existir, uma tabela ter registros — difícil de fazer bem no Step Functions.

---

## 7. Backfill: reprocessar datas passadas

```bash
# Reprocessa de 2026-06-01 até 2026-06-30
airflow dags backfill pipeline_medalhao --start-date 2026-06-01 --end-date 2026-06-30
```

Essa é uma das maiores vantagens operacionais do Airflow em pipelines
incrementais (parametrize os jobs por `{{ ds }}` — a data lógica da execução).

---

## 8. Operação e boas práticas

- **DAGs idempotentes:** rodar a mesma data duas vezes não deve duplicar dados
  (combine com o `overwrite` por partição ou Iceberg — Módulo 06).
- **Parametrize por `{{ ds }}`:** passe a data de execução para os jobs como
  argumento, em vez de ler "tudo que existe".
- **Não faça processamento pesado no topo do DAG:** lógica de Python ali roda
  no scheduler. Pesado vai numa task (`PythonOperator`/container).
- **Monitore:** `email_on_failure`, integração com Slack, alertas de SLA miss.
- **Versionamento:** DAGs e requirements no Git; CI testa `airflow dags test`.

---

## Exercícios do módulo

**Ex. 1 — Leia a DAG:** Abra `airflow/dags/medalhao_dag.py`. Por que
`wait_for_completion=True` é essencial para a ordem Bronze → Silver → Gold? ¹

**Ex. 2 — Validar topologia (sem AWS):** Instale o Airflow localmente (ver
`airflow/README.md`) e rode `airflow dags test pipeline_medalhao 2026-07-01`
para confirmar que a DAG parseia e a ordem das tasks está correta.

**Ex. 3 — Sensor:** Adicione um `S3KeySensor` antes do Bronze que só libere o
pipeline quando existir um arquivo em `landing/vendas/dt={{ ds }}/`.

**Ex. 4 — Paralelo:** Modifique a DAG para que, após o Bronze, o Silver de
vendas e o Silver de clientes rodem em paralelo (`bronze >> [sv, sc] >> gold`).

**Ex. 5 — Parametrização:** Passe `{{ ds }}` como argumento do job Bronze (ex.:
`--INPUT_PATH=s3://bucket/landing/vendas/dt={{ ds }}/`) para tornar o pipeline
data-aware. Teste o backfill de um intervalo.

**Ex. 6 — MWAA (opcional):** Provisione o módulo `mwaa` (atenção ao custo),
suba a DAG e o `requirements.txt` para o bucket de DAGs e dispare pelo console.

**Ex. 7 — Comparação (escrita):** Em 1 parágrafo, justifique quando você
escolheria Step Functions e quando escolheria Airflow para este mesmo data
lake. Considere equipe, custo e necessidade de backfill. ²

¹ *Porque cada task só "termina" quando o job Glue correspondente termina
(com `wait_for_completion=True`). Sem isso, a task disparava o job e marcava
sucesso imediatamente — o Silver começaria enquanto o Bronze ainda corria,
quebrando a ordem e lendo dados incompletos.*

² *Step Functions se a equipe quer serverless puro na AWS, custo baixo por
transição, fluxo estável e sem necessidade de backfill/sensores. Airflow se
há lógica complexa, sensores (esperar arquivo/partição), reprocessamento de
datas (backfill), integrações multi-cloud, ou expertise Python já instalada —
arcando com o custo/operacao do MWAA ou de um Airflow autogerenciado.*
