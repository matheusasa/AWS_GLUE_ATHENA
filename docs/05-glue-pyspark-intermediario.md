# Módulo 05 — Glue + PySpark: Intermediário

## Objetivos

Dominar as transformações do dia a dia: **schema explícito**, **casting e limpeza**, **joins**, **agregações**, **window functions**, **deduplicação** e **escrita particionada** de qualidade. Ao final, você escreve pipelines de Prata consistentes.

---

## 1. Definindo schema explicitamente (pare de usar `inferSchema`)

```python
from pyspark.sql.types import (
    StructType, StructField, IntegerType, StringType,
    DoubleType, TimestampType
)

schema_vendas = StructType([
    StructField("id_venda",     IntegerType(),  nullable=False),
    StructField("id_cliente",   IntegerType(),  nullable=True),
    StructField("id_produto",   IntegerType(),  nullable=True),
    StructField("quantidade",   IntegerType(),  nullable=True),
    StructField("valor_unit",   DoubleType(),   nullable=True),
    StructField("data_venda",   TimestampType(), nullable=True),
    StructField("canal",        StringType(),   nullable=True),
])

df = (
    spark.read
    .option("header", True)
    .option("timestampFormat", "yyyy-MM-dd HH:mm:ss")
    .schema(schema_vendas)
    .csv("s3://meu-bucket/bronze/vendas/")
)
```

Vantagens: **sem passada extra** nos dados (mais rápido), **sem erros de inferência** (ex.: CEP virando inteiro e perdendo zeros), e o pipeline quebra cedo se a origem muda de schema (falha explícita > dado silenciosamente errado).

> Para fontes voláteis, use `schema_evolution` (Parquet/Iceberg) ou valide com `df.printSchema()` comparando ao esperado.

---

## 2. Casting e limpeza de tipos

```python
from pyspark.sql.functions import col, to_timestamp, to_date, trim, regexp_replace

df_limpo = (
    df
    # texto com espaços e vírgula decimal vinda de planilha
    .withColumn("valor_unit", regexp_replace(col("valor_unit"), ",", "."))
    .withColumn("valor_unit", col("valor_unit").cast("double"))
    # datas como texto -> tipo real
    .withColumn("data_venda", to_timestamp(col("data_venda")))
    .withColumn("dt", to_date(col("data_venda")))
    # remove espaços de campos categóricos
    .withColumn("canal", trim(col("canal")))
)
```

**Padrão de Prata:** tipos sempre corretos (`date`/`timestamp`, `double`, não strings), nomes padronizados (snake_case), categorias sem espaços.

---

## 3. Enriquecendo: JOIN entre tabelas

Cenário: cruzar `vendas` com `clientes` e `produtos`.

```python
from pyspark.sql.functions import col

df_clientes = spark.table("clientes_prata")     # via Catálogo
df_produtos = spark.table("produtos_prata")

df_enriquecido = (
    df_limpo
    .join(df_clientes, "id_cliente", "left")
    .join(df_produtos, "id_produto", "left")
)

# Cuidado: joins repetem colunas com mesmo nome. Use select para escolher:
df_enriquecido = df_enriquecido.select(
    "id_venda", "data_venda", "canal",
    col("nome").alias("cliente_nome"),
    col("regiao").alias("cliente_regiao"),
    col("categoria").alias("produto_categoria"),
    col("valor_unit"),
    col("quantidade"),
)
```

**Tipos de join:** `inner`, `left`, `right`, `outer`, `left_anti` (linha de A sem correspondência em B — ótimo para QA: "quais vendas não têm cliente?"), `left_semi` (só as de A que existem em B, sem colunas de B).

### `broadcast` join (otimização)

Se uma das tabelas é **pequena** (ex.: dimensão de ~50 MB), force o broadcast — o Spark a envia inteira a cada executor, evitando o *shuffle*:

```python
from pyspark.sql.functions import broadcast

df_enriquecido = df_limpo.join(broadcast(df_produtos), "id_produto", "left")
```

Isso pode acelerar drasticamente. Veremos tuning fino no Módulo 06.

---

## 4. Colunas calculadas e valor total

```python
from pyspark.sql.functions import col, expr, when

df_enriquecido = df_enriquecido.withColumn(
    "valor_total",
    col("valor_unit") * col("quantidade")
).withColumn(
    "faixa_valor",
    when(col("valor_total") < 100, "baixo")
    .when(col("valor_total") < 1000, "medio")
    .otherwise("alto")
)
```

---

## 5. Agregações clássicas

```python
from pyspark.sql.functions import sum as _sum, count, avg, max as _max, round

resumo = (
    df_enriquecido
    .groupBy("cliente_regiao", "produto_categoria")
    .agg(
        _sum("valor_total").alias("receita"),
        count("id_venda").alias("qtd_vendas"),
        round(avg("valor_total"), 2).alias("ticket_medio"),
        _max("data_venda").alias("ultima_venda"),
    )
)
```

---

## 6. Window functions (análises por partição)

Útil para rankings, médias móveis, "primeira/última compra do cliente".

```python
from pyspark.sql.functions import row_number, desc
from pyspark.sql.window import Window

w = Window.partitionBy("id_cliente").orderBy(desc("data_venda"))

df_com_rank = (
    df_enriquecido
    .withColumn("rn", row_number().over(w))
)

# Top 3 compras de cada cliente
top3 = df_com_rank.filter(col("rn") <= 3)
```

Outras: `rank`, `dense_rank`, `lag`, `lead`, `sum().over(Window...)` para acumulado/média móvel.

---

## 7. Deduplicação

### Por chave + mantendo o mais recente

```python
from pyspark.sql.window import Window
from pyspark.sql.functions import col, row_number

w = Window.partitionBy("id_venda").orderBy(col("ingestao_ts").desc())
df_unico = (
    df.withColumn("rn", row_number().over(w))
      .filter(col("rn") == 1)
      .drop("rn")
)
```

### Simples por coluna (dropDuplicates)

```python
df_unico = df.dropDuplicates(["id_venda"])
```

> `dropDuplicates` mantém uma linha arbitrária. Para regra de negócio ("a mais recente"), use o padrão com `row_number` acima.

---

## 8. Tratando nulos e qualidade

```python
from pyspark.sql.functions import col, when, lit

# Regra: se quantidade veio nula, inviabiliza a venda -> descarta
df_q = df_enriquecido.filter(col("quantidade").isNotNull())

# Preenche nulos onde faz sentido
df_q = df_q.fillna({"cliente_regiao": "NAO_INFORMADO", "produto_categoria": "SEM_CATEGORIA"})

# Coluna "is_valid" para relatório de qualidade
df_q = df_q.withColumn(
    "is_valid",
    when(col("valor_total") > 0, True).otherwise(False)
)
```

O Glue ainda oferece **Data Quality Rules** (declarativas) e o **ResolveChoice** para DynamicFrames com tipos mistos:

```python
dyf = dyf.resolveChoice(specs=[("valor", "cast:double")])
```

---

## 9. Escrita de Prata: Parquet particionado e formato

```python
from pyspark.sql.functions import year, month, dayofmonth

(df_q
    .withColumn("ano",  year("data_venda"))
    .withColumn("mes",  month("data_venda"))
    .write
    .mode("append")               # append: soma partições; cuidado com overwrite em incremental
    .format("parquet")
    .partitionBy("ano", "mes")
    .option("compression", "snappy")
    .save("s3://meu-bucket/prata/vendas/"))
```

Boas práticas de partição:

- Particione por colunas de **baixa cardinalidade** usadas em filtros (`ano`, `mes`, `regiao`).
- Evite **sobreparticionar** (milhões de pastas pequenas) — mata a performance. Regra geral: cada partição com alguns MB a centenas de MB.
- Em incremental, use **`append`** + dedup no consumo, ou formatos transacionais (**Iceberg**) que resolvem isso melhor.

---

## 10. ApplyMapping (jeito Glue de renomear/retipar)

```python
from awsglue.dynamicframe import DynamicFrame

dyf = DynamicFrame.fromDF(df, glueContext, "dyf")
dyf2 = ApplyMapping.apply(
    dyf,
    mappings=[
        ("id_venda", "int",    "id_venda",   "int"),
        ("valor",    "string", "valor",      "double"),
        ("data_venda","string","data_venda", "timestamp"),
    ],
)
df = dyf2.toDF()
```

Equivalente a vários `cast`/`withColumnRenamed`, mas explícito — comum em jobs migrados do Glue Studio visual.

---

## 11. Exemplo completo: Bronze → Prata

O script `glue-jobs/silver_transform.py` do projeto consolida tudo isso: lê vendas/clientes/produtos da Bronze, limpa, enriquece com joins, deduplica, calcula `valor_total` e grava Parquet particionado. Estude-o como referência.

---

## Exercícios do módulo

**Ex. 1 — Schema rígido:** Pegue o `bronze_ingest.py` e troque `inferSchema` por um `StructType`. Force um erro de tipo (suba um CSV com uma letra no campo numérico) e observe a falha explícita.

**Ex. 2 — Join + broadcast:** Cruzar `vendas` × `produtos`. Meça o tempo do job com e sem `broadcast(df_produtos)`. (Veremos como medir no Módulo 06.)

**Ex. 3 — Top 3:** Para cada cliente, listar suas 3 maiores compras (`valor_total`). Dica: `window` + `row_number`.

**Ex. 4 — Dedup com regra:** Simule duplicidade de `id_venda` (dois registros com `ingestao_ts` diferentes). Mantenha só o mais recente.

**Ex. 5 — Particionamento:** Grave a Prata particionada por `ano`/`mes`. No Athena, rode duas consultas (uma filtrando `dt`, outra não) e compare o **Bytes Scanned** — veja o ganho do particionamento.

**Ex. 6 — Pergunta:** Quando um `left_anti` join seria útil num pipeline de dados? ¹

¹ *Para **qualidade/auditoria**: "quais registros de A não encontraram correspondência em B?". Ex.: vendas sem cliente cadastrado, ou produtos sem categoria — casos que indicam problema na origem e precisam de investigação antes de chegar ao Ouro.*
