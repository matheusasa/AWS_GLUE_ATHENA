# Módulo 06 — Glue + PySpark: Avançado

## Objetivos

Levar seus jobs ao nível de produção: **performance/tuning**, **cargas incrementais com bookmarks**, **UDFs**, **formatos modernos (Iceberg)**, **evitar arquivos pequenos**, **observabilidade** e **tratamento de erros**. É o módulo que separa quem "roda job" de quem constrói pipelines robustos.

---

## 1. Entendendo partições e shuffles (a chave da performance)

O Spark divide os dados em **partições** distribuídas pelos executors. Operações **narrow** (map, filter, select) rodam dentro de cada partição, sem movimento de dados. Operações **wide** (`groupBy`, `join`, `distinct`, `orderBy`) exigem **shuffle** — os dados são reorganizados pela rede entre executors. **Shuffle é caro** (I/O, rede, disco). Quase todo tuning é "reduzir o shuffle".

```python
from pyspark.sql.functions import broadcast, approx_count_distinct

# Veja a cardinalidade antes de decidir estratégia de join/partição
card = df.agg(approx_count_distinct("id_cliente")).collect()[0][0]
```

### Adaptive Query Execution (AQE)

No Glue 4 (Spark 3.x), ative o **AQE** — o Spark reajusta partições e troca tipo de join em runtime:

```python
spark = glueContext.spark_session
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
```

AQE une partições pequenas (menos arquivos na saída) e corrige **skew** (uma partição muito maior que as outras trava o job).

---

## 2. Tuning de joins (onde o tempo se vai)

| Situação | Estratégia |
|---|---|
| Uma tabela é pequena (< ~100 MB) | `broadcast(tabela_pequena)` — sem shuffle |
| Ambas grandes, chave uniforme | SortMergeJoin (padrão no Spark 3) |
| Chave com skew (uma chave domina) | AQE `skewJoin` + ou `salting` |
| Join por chave desigual/condição complexa | BroadcastRangeJoin ou reparticionar manualmente |

### Broadcast — quando NÃO usar

Broadcast envia a tabela inteira a **todos** executors. Se você broadcast uma tabela **grande**, estoura memória (OOM). Limite seguro: o `spark.sql.autoBroadcastJoinThreshold` (default 10 MB). Aumente com cuidado:

```python
spark.conf.set("spark.sql.autoBroadcastJoinThreshold", "104857600")  # 100 MB
```

---

## 3. Reparticionamento manual

```python
# Antes de um join/agregação pesada por uma chave específica
df = df.repartition(200, "id_cliente")

# Antes de escrever, controlar nº de arquivos de saída
df = df.repartition(50)            # 200 -> 50 arquivos (junta)
df = df.coalesce(10)               # só diminui (sem shuffle, mais barato p/ reduzir)
```

**Padrão de saída saudável:** arquivos entre **~128 MB e 1 GB** de Parquet. Milhares de arquivos de 1 KB ("small files problem") arrasam Athena/Glue.

---

## 4. Evitando o "small files problem"

```python
(df
    .repartitionByRange(50, "ano", "mes")   # ordena e junta
    .write
    .option("maxRecordsPerFile", 1_000_000)
    .partitionBy("ano", "mes")
    .parquet("s3://.../prata/vendas/"))
```

Ou consolide periodicamente os dados antigos. Em volumes altos, formatos como **Iceberg** (seção 9) resolvem com `rewrite_data_files`.

---

## 5. Caching e checkpoint (use com consciência)

```python
df_cached = df.filter(...).cache()      # mantém em memória após 1ª action
df_cached.count()                        # materializa o cache

# Em pipelines longos/iterativos com shuffles, checkpoint para cortar o plano
sc.setCheckpointDir("s3://.../_checkpoint/")
df.checkpoint(eager=True)
```

**Regra:** faça cache só se o DataFrame for **reutilizado** várias vezes. Caching sem reuso é desperdício de memória. E lembre de `unpersist()` ao terminar.

---

## 6. UDFs (e por que evitar)

UDFs em Python quebram a otimização do Spark (viram "caixa preta", não há pushdown, serialização Python lenta). **Prefira funções nativas** de `pyspark.sql.functions`.

```python
# ❌ Lento (UDF Python)
from pyspark.sql.functions import udf
from pyspark.sql.types import DoubleType

@udf(DoubleType())
def desconto(valor):
    return valor * 0.9

df = df.withColumn("com_desc", desconto(col("valor")))

# ✅ Rápido (nativa)
df = df.withColumn("com_desc", col("valor") * lit(0.9))
```

Se precisar de lógica complexa, considere **`pandas_udf`** (vectorized, Apache Arrow) — ordens de magnitude mais rápido que UDF Python tradicional.

```python
from pyspark.sql.functions import pandas_udf

@pandas_udf("double")
def desconto_vetorial(s):
    return s * 0.9
```

---

## 7. Cargas incrementais com Bookmarks

O **job bookmark** registra "até onde o job processou". Na próxima execução, o Glue lê só o **novo**. Essencial para Bronze/Prata de chegada contínua.

**Como ativar:**

1. No job: `--job-bookmark-option=job-bookmark-enable`.
2. **Todo** `DynamicFrame` de origem precisa de um `transformation_ctx` único.
3. Para recomeçar do zero: `--job-bookmark-option=job-bookmark-pause` e depois reset via CLI/console.

```python
dyf = glueContext.create_dynamic_frame.from_catalog(
    database="datalake_db",
    table_name="vendas_bronze",
    transformation_ctx="vendas_bronze_ctx",   # <-- obrigatório p/ bookmark
)
```

> **Limitação:** bookmarks funcionam bem com `from_catalog` em fontes suportadas (S3 com manifesto, JDBC, Kinesis). Para Parquet puro no S3, combine com particionamento por data ou use **Iceberg** para controle transacional robusto.

### Padrão de carga incremental manual (sem bookmark)

```python
from pyspark.sql.functions import max as _max, lit, current_timestamp

# Lê a "marca d'água" da última carga (ex.: num arquivo de controle ou tabela)
ultima = spark.read.table("controle_carga").filter("tabela='vendas'").first()["watermark"]

# Lê só o que veio depois
df_novo = spark.read.parquet("s3://.../bronze/vendas/").filter(col("ingestao_ts") > lit(ultima))

# ... processa df_novo ...

# Atualiza a marca d'água
nova_marca = df_novo.agg(_max("ingestao_ts")).first()[0]
# gravar nova_marca de volta no controle
```

---

## 8. Pushdown predicate e leitura seletiva

```python
from awsglue.dynamicframe import DynamicFrame

# Lê só a partição 2026/06 (não varre o bucket inteiro!)
dyf = glueContext.create_dynamic_frame.from_catalog(
    database="datalake_db",
    table_name="vendas_bronze",
    push_down_predicate = "(ano == '2026' and mes == '06')",
    transformation_ctx="vendas_bronze_ctx",
)
```

Isso usa o **partition pruning** do Catálogo: o Glue lista as partições, filtra e lê só as pastas relevantes. Pode reduzir de horas para minutos.

---

## 9. Formatos de tabela modernos: Apache Iceberg

Para dados que **mudam** (updates/deletes), Parquet puro é sofrido. **Iceberg** (e Hudi/Delta) trazem **transações ACID**, **time travel**, **schema evolution** e **merge/upsert** sobre o S3.

### Habilitar no Glue 4

```python
spark = glueContext.spark_session
spark.conf.set("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", "s3://meu-bucket/warehouse")
spark.conf.set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
```

### Upsert (merge) — impossível com Parquet puro

```python
# Tabela Iceberg registrada no Catálogo
spark.sql("""
MERGE INTO glue_catalog.datalake_db.vendas_prata AS t
USING df_updates AS s
  ON t.id_venda = s.id_venda
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")
```

### Manutenção (juntar arquivos pequenos)

```sql
CALL glue_catalog.system.rewrite_data_files('datalake_db.vendas_prata');
```

Use Iceberg quando precisar de **idempotência** (reprocessar sem duplicar), **upserts** ou **histórico**. Para append-only simples, Parquet particionado ainda é mais leve.

---

## 10. Observabilidade e métricas

```python
from awsglue.context import GlueContext

# Conta linhas e publica como métrica visível no CloudWatch/Job Run
glueContext.getMetrics().setMetricsProperty(dyf, "recordCount", str(dyf.count()))

# Logger estruturado
logger = glueContext.get_logger()
logger.info(f"Linhas processadas: {df.count()}")
```

Acompanhe no **CloudWatch Metrics** (DPUs consumidos, linhas lidas/escritas) e no **Job Run Profile** do Glue Studio (mostra estágio por estágio do Spark, onde o tempo vai).

---

## 11. Tratamento de erros, retries e idempotência

- **Idempotência:** reprocessar um job **não** deve duplicar dados. Use Iceberg `MERGE`, ou dedupe no consumo, ou `INSERT OVERWRITE` da partição.
- **Retries:** configure no job (tentativas com backoff). Em pipelines, use **Step Functions** para orquestrar e retentar estágios.
- **Dead-letter:** dados que falham (parse, schema) vão para um bucket/prefixo `_quarentena` para análise posterior, em vez de derrubar o job inteiro.

```python
# Padrão quarentena
erros = df.filter(~col("is_valid"))
ok     = df.filter(col("is_valid"))

(erros.write.mode("append").parquet("s3://.../quarentena/vendas/"))
```

---

## 12. Otimização de custo

- **Desligue jobs** quando não usar (`terraform destroy` no dev).
- Escolha **worker type** certo: `G.1X` para maioria; `G.2X` para memória; `G.025X` (flex) para dev barato.
- **Reduza DPUs** até o tempo de execução começar a subir — ponto ótimo.
- Evite `count()`/`show()` em datasets gigantes só para "verificar" — use amostragem (`sample`).
- Particione e use **Parquet/Iceberg** para reduzir bytes lidos no Athena (você paga por TB).

---

## Checklist de "pronto para produção"

- [ ] Schema explícito, sem `inferSchema`.
- [ ] Particionamento adequado, sem small files.
- [ ] AQE ligado; joins otimizados (broadcast onde couber).
- [ ] Idempotente (reprocessar não duplica).
- [ ] Bookmark/incremental configurado (se aplicável).
- [ ] Tratamento de nulos + coluna de qualidade/validação.
- [ ] Logs/métricas; dados de erro em quarentena.
- [ ] Timeout definido; retries configurados.
- [ ] Tags e role com least-privilege.

---

## Exercícios do módulo

**Ex. 1 — Medir antes/depois:** Pegue o `silver_transform.py`. Rode sem AQE. Depois ligue AQE + `coalescePartitions`. Compare o tempo e o número de arquivos gerados.

**Ex. 2 — Broadcast vs sort-merge:** Faça um join grande. Force `broadcast` numa tabela de 500 MB (vai falhar de OOM ou ficar lento). Em seguida, faça o broadcast só numa tabela pequena. Documente o comportamento.

**Ex. 3 — Bookmark incremental:** Configure o job com `job-bookmark-enable` e `transformation_ctx` em todas as origens. Suba novos arquivos e rode de novo: confirme que só o novo foi processado. Faça `reset` e rode tudo.

**Ex. 4 — Iceberg upsert:** Crie uma tabela Iceberg, insira vendas, depois faça `MERGE` com "correções" (mesmo `id_venda`). Confirme que **atualizou** e não duplicou.

**Ex. 5 — Quarentena:** Adicione ao seu job uma coluna `is_valid` e grave os inválidos em `s3://.../quarentena/`. Rode com dados propositalmente sujos.

**Ex. 6 — Pergunta:** Por que uma UDF Python "simples" pode deixar um job muito mais lento que a função nativa equivalente? ¹

¹ *Porque a UDF Python quebra o pipeline de otimização do Catalyst (sem pushdown, sem codegen) e força serialização entre JVM e processo Python, linha a linha. A função nativa roda dentro da JVM com codegen, sem o custo de contexto cruzado — por isso pode ser ordens de magnitude mais rápida.*
