# Módulo 04 — AWS Glue + PySpark: Fundamentos

## Objetivos

Entender como o **AWS Glue** roda **PySpark**, dominar os objetos básicos (SparkContext, GlueContext, DynamicFrame, DataFrame) e escrever seu **primeiro job** funcional. A partir daqui o código é concreto e roda de verdade.

---

## 1. Como o Glue funciona por baixo dos panos

Quando você dispara um **Glue Job** em PySpark, acontece o seguinte:

1. O Glue sobe um cluster Spark **serverless** (você escolhe *DPUs* — Data Processing Units, que combinam CPU/memória).
2. Distribui seu script para os *executors*.
3. O Spark lê a fonte, particiona os dados entre os executors, processa em paralelo e grava o destino.
4. Ao fim, o cluster é **destruído** (você paga pelo tempo de execução).

Você escreve PySpark padrão; o Glue adiciona o **GlueContext** (com `DynamicFrames`) e conectores nativos para S3, JDBC, Catálogo, etc.

> **Conceito Spark:** Spark é um motor de processamento **distribuído em memória**. A unidade de dados é o **DataFrame** (tabela distribuída) ou **RDD**. As operações são **lazy** (só rodam numa *action* como `write`, `show`, `count`).

---

## 2. O esqueleto de todo job Glue em PySpark

Todo job começa mais ou menos assim:

```python
# glue-jobs/bronze_ingest.py (versão didática reduzida)
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

# 1) Lê parâmetros passados na hora de criar o job no Glue
args = getResolvedOptions(sys.argv, ["JOB_NAME", "INPUT_PATH", "OUTPUT_PATH"])

# 2) Cria o SparkContext e o GlueContext (uma vez por job)
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# 3) Inicializa o Job (necessário para bookmarks, métricas, etc.)
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# 4) ... aqui vai a sua lógica de leitura/transformação/escrita ...

# 5) Encerra
job.commit()
```

Por que cada peça?

- **`getResolvedOptions`**: lê os parâmetros que você define ao criar o job (ex.: caminhos de origem/destino). Torna o job reutilizável sem mexer no código.
- **`SparkContext`**: a conexão com o cluster Spark. Sempre uma por aplicação.
- **`GlueContext`**: envolve o SparkContext e adiciona os DynamicFrames e leitores/gravadores do Glue.
- **`Job.init` / `Job.commit`**: habilitam **bookmarks** (controle de quanto já processou — vital para cargas incrementais) e métricas.

---

## 3. DataFrame vs. DynamicFrame

| | **DataFrame (PySpark puro)** | **DynamicFrame (Glue)** |
|---|---|---|
| Schema | **Rígido** (uma coluna, um tipo) | **Flexível** (uma coluna pode ter vários tipos) |
| Erros em schema sujo | Quebra | Tola (guarda o valor como `ChoiceType`) |
| API | Rica, padrão Spark | Mais simples, com `apply_mapping`, `relationalize` |
| Quando usar | Sempre que possível (mais performático) | Dados crus/sujos da Bronze, origens imprevisíveis |

**Regra prática:** use **DynamicFrame na entrada** (tolerância a sujeira) e **converta para DataFrame** (`dynamicFrame.toDF()`) para transformações mais ricas e performáticas. Volte a DynamicFrame só se precisar dos métodos específicos do Glue.

```python
dyf = glueContext.create_dynamic_frame.from_catalog(
    database="meu_db", table_name="vendas_bronze"
)
df = dyf.toDF()                      # agora tenho um DataFrame Spark "normal"
print(df.printSchema())              # inspeciona as colunas
print(df.show(5))                    # mostra 5 linhas
```

---

## 4. DataFrame: operações essenciais (revisão de PySpark)

Se você nunca usou PySpark, estes são os verbos que mais aparecem:

```python
from pyspark.sql.functions import col, sum as _sum, count, avg, to_date, year

# Selecionar colunas
df.select("cliente", "valor")

# Filtrar
df.filter(col("valor") > 100)

# Criar/transformar coluna
df.withColumn("ano", year(col("data_venda")))

# Renomear
df.withColumnRenamed("valor", "valor_total")

# Agregar
df.groupBy("cliente").agg(
    _sum("valor").alias("total"),
    count("*").alias("qtd_pedidos")
)

# Ordenar
df.orderBy(col("total").desc())

# Descartar nulos
df.dropna()
df.fillna(0, subset=["valor"])
```

**Lazy evaluation:** as transformações só "rodam" quando você chama uma **action**: `show()`, `count()`, `collect()`, `write()`. Isso permite ao Spark otimizar o plano inteiro antes de executar. Por isso, **encadeie** transformações e deixe a action por último.

---

## 5. Lendo e escrevendo no S3

### Lendo CSV (comum na Bronze)

```python
df = (
    spark.read
    .option("header", True)
    .option("inferSchema", True)      # em produção, defina o schema explicitamente
    .csv("s3://meu-bucket/bronze/vendas/")
)
```

> **Evite `inferSchema` em produção.** Ele faz uma passada extra nos dados e pode errar o tipo. **Defina o schema** com `StructType` (veremos no Módulo 05) — é mais rápido e seguro.

### Escrevendo Parquet particionado (comum na Prata/Ouro)

```python
(
    df.write
    .mode("overwrite")
    .format("parquet")
    .partitionBy("ano", "mes")
    .save("s3://meu-bucket/prata/vendas/")
)
```

Por que **particionar**? Consultas que filtram por `ano`/`mes` leem só as pastas relevantes — muito menos dados lidos, menos custo no Athena/Glue.

---

## 6. Usando o Catálogo Glue (a forma "nativa")

Em vez de caminhos hardcoded, referencie **tabelas do Catálogo**:

```python
# Leitura via Catálogo
dyf = glueContext.create_dynamic_frame.from_catalog(
    database="datalake_db",
    table_name="vendas_bronze",
    # transformation_ctx="vendas"  # necessário p/ bookmarks funcionar
)

# Escrita via Catálogo (cria/atualiza a tabela e grava no S3)
glueContext.write_dynamic_frame.from_catalog(
    frame=dyf,
    database="datalake_db",
    table_name="vendas_prata",
)
```

O `transformation_ctx` (um nome único para cada operação) é **obrigatório** para bookmarks funcionarem — não esqueça.

---

## 7. Rodando seu primeiro job

### Caminho A — pela infra do projeto (recomendado)

1. Suba a infra com Terraform (Módulo 08 / pasta `terraform/envs/dev`). Isso cria o bucket, o Catálogo, a role do Glue e o **próprio job** (módulo `glue_job`).
2. Faça upload dos dados de exemplo (`data/sample/`) para o prefixo `bronze/`.
3. No console do **Glue → Jobs**, abra seu job, clique em **Run**.
4. Acompanhe em **Runs** e veja os logs no **CloudWatch Logs**.

### Caminho B — console (para entender)

1. Glue Studio → **Jobs → Visual** ou **Script**.
2. Cole o script `bronze_ingest.py`.
3. Na aba **Details**, defina o **IAM Role**, os parâmetros (`INPUT_PATH`, `OUTPUT_PATH`) e o número de DPUs.
4. **Save** e **Run**.

---

## 8. Parâmetros importantes do Glue Job

Ao criar o job (ou no Terraform), configure:

- **Type:** `GlueSpark` (PySpark).
- **Glue version:** `4.0` (Spark 3.3, Python 3.10) — prefira a mais recente.
- **Worker type:** `G.1X` (1 DPU = 4 vCPU, 16 GB) ou `G.2X`. Para teste, `Standard`.
- **Number of workers:** comece com 2–5 e ajuste.
- **Job parameters (key/value):** `INPUT_PATH`, `OUTPUT_PATH`, `--job-bookmark-option=job-bookmark-enable`.
- **Timeout:** sempre defina (evita job travado cobrando infinitamente).

---

## 9. Erros clássicos do iniciante

- Esquecer `job.commit()` → bookmarks não persistem.
- Misturar Spark 2 e 3 → APIs mudaram (`spark.sql` vs `sc.sql`, funções de `pyspark.sql.functions`).
- Usar `show()` em produção em datasets gigantes → traga pra memória com cuidado (`take`, `limit`).
- Caminhos S3 errados (sem `s3://` ou com barra a mais/menos).
- Não dar `transformation_ctx` → bookmarks não funcionam.
- Rodar sem **timeout** → um erro pendurado custa caro.

---

## Exercícios do módulo

**Ex. 1 — Script mínimo:** Escreva um job que leia o `data/sample/vendas.csv` do S3 (após subir a infra), conte as linhas e imprima com `logger`. Rode no Glue e confira no CloudWatch.

**Ex. 2 — Schema à mão:** Substitua `inferSchema` por um `StructType` explícito (id INT, cliente STRING, valor DOUBLE, data_venda DATE). Reaplique.

**Ex. 3 — DynamicFrame → DataFrame:** Leia com `create_dynamic_frame.from_catalog`, converta com `.toDF()`, e faça um `groupBy("cliente").sum("valor")`.

**Ex. 4 — Escrita particionada:** Grave o resultado como **Parquet particionado por ano** no S3. Abra no Athena e faça um `SELECT` — veja a diferença de custo comparado a ler um CSV gigante.

**Ex. 5 — Pergunta:** Por que as transformações em Spark "não acontecem" até você chamar `write` ou `show`? ¹

¹ *Porque o Spark usa **lazy evaluation**: ele monta um plano lógico das transformações e só executa numa *action*. Assim ele otimiza o plano inteiro (reordena, faz pushdown de filtros) antes de tocar nos dados — economizando I/O e memória.*
