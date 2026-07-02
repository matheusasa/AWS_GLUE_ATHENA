# Módulo 07 — Arquitetura Medalhão

## Objetivos

Entender a **Arquitetura Medalhão** (Bronze / Prata / Ouro), o que define cada camada, e como mapeá-la para **S3 + Glue + PySpark** de ponta a ponta.

---

## 1. O que é e por que existe

A medalhão (popularizada pela Databricks) organiza um data lake em **três camadas lógicas**, cada uma com propósito, contrato e nível de qualidade diferentes. A ideia é separar **chegada dos dados** (bruta) de **qualidade analítica** (curada), com transformações progressivas.

Por que usar? Porque jogar tudo num bucket só vira "data swamp": ninguém confia nos dados, schemas conflitam, reprocessar é caótico. As camadas criam **progressão de confiança** e **contratos claros** entre times.

```
Fontes →  BRONZE  →  PRATA  →  OURO  →  BI / ML / APIs
        (igual à  (limpa,   (pronta
         origem)   padronizada)  para consumo)
```

---

## 2. Camada Bronze — "o que chegou"

**Propósito:** guardar os dados **exatamente como vieram da fonte**, com o mínimo de transformação possível.

- Formato original da fonte (CSV, JSON, logs) **ou** convertido para um formato colunar **sem alterar o conteúdo** (recomendado para economizar).
- **Adiciona** apenas metadados de controle: `ingestao_ts` (quando chegou), `arquivo_origem`, `batch_id`.
- **Append-only**: nunca altera o histórico. É o "registro oficial".
- Esquema: **flexível/tolerante** (pode haver colunas a mais/menos conforme a fonte evolui).
- Não descarta nada — inclusive erros (eles vão para análise de qualidade).

### Pseudocódigo Bronze

```python
# Lê CSV cru, adiciona colunas de controle e grava Parquet (sem mexer no conteúdo)
df = (spark.read
        .option("header", True)
        .option("inferSchema", True)        # bronze pode tolerar inferência
        .csv(f"s3://lake/bronze/landing/vendas/{batch_id}/"))

df = (df
        .withColumn("ingestao_ts", current_timestamp())
        .withColumn("arquivo_origem", input_file_name())
        .withColumn("batch_id", lit(batch_id)))

(df.repartitionByRange(20, "ingestao_ts")
   .write.mode("append")
   .partitionBy("dt_ingestao")
   .parquet("s3://lake/bronze/vendas/"))
```

> **Regra de ouro da Bronze:** se um dado está na Bronze, ele **representa fielmente** a fonte num momento do tempo. Reprocessável a qualquer hora.

---

## 3. Camada Prata — "limpa e padronizada"

**Propósito:** dados **limpos, tipados, padronizados, enriquecidos** e deduplicados — o "coração" do lake, fonte de verdade corporativa.

- Tipos corretos (`date`, `double`, `int`), nomes padronizados (snake_case).
- Dados sujos tratados (nulos, encoding, separador decimal).
- **Deduplicação** (mesma entidade representada uma vez).
- **Joins** com dimensões (cliente, produto) para enriquecer.
- Esquema **estável e versionado** (contrato para o time).
- Formato **Parquet** (ou Iceberg) particionado para consulta eficiente.

### Pseudocódigo Prata

```python
# Lê Bronze, limpa, enriquece, deduplica e grava Prata
df = spark.read.parquet("s3://lake/bronze/vendas/").filter(col("dt_ingestao") == lit(hoje))

df = (df
        .withColumn("valor_unit", col("valor_unit").cast("double"))
        .withColumn("data_venda", to_timestamp("data_venda"))
        .dropDuplicates(["id_venda"])
        .join(broadcast(clientes), "id_cliente", "left")
        .join(broadcast(produtos), "id_produto", "left")
        .withColumn("valor_total", col("valor_unit") * col("quantidade")))

(df.write.mode("overwrite")
   .partitionBy("ano", "mes")
   .parquet("s3://lake/prata/vendas/"))
```

A Prata é onde **90% da lógica de negócio de limpeza** mora. BI e ML podem consumir diretamente daqui.

---

## 4. Camada Ouro — "pronta para consumo"

**Propósito:** dados **agregados e modelados para um caso de consumo específico** (dashboard, relatório, modelo de ML, API).

- Agregações de negócio (`GROUP BY` por região/mês/categoria).
- Modelagem dimensional (esquema estrela: fatos + dimensões) para BI.
- Métricas calculadas (KPIs: receita, ticket médio, NPS).
- Pequena, rápida, **pré-filtrada** e otimizada para leitura.
- Pode ser **múltipla**: um Ouro de vendas, outro de marketing, outro de logística.

### Pseudocódigo Ouro

```python
# Lê Prata, agrega para um dashboard de vendas por região/mês
df_prata = spark.table("glue_catalog.datalake_db.vendas_prata")

ouro = (df_prata
          .groupBy("cliente_regiao", "produto_categoria", "ano", "mes")
          .agg(_sum("valor_total").alias("receita"),
               count("id_venda").alias("qtd_vendas"),
               round(avg("valor_total"), 2).alias("ticket_medio")))

(ouro.write.mode("overwrite")
     .partitionBy("ano", "mes")
     .parquet("s3://lake/ouro/vendas_regiao_mes/"))
```

Ouro é o que o QuickSight/Athena/Redshift consome. Mudou o dashboard? Cria-se outro Ouro — a Prata permanece estável.

---

## 5. Contratos entre camadas (resumo)

| Aspecto | Bronze | Prata | Ouro |
|---|---|---|---|
| Fidelidade à fonte | Máxima | Transformada | Agregada/modelada |
| Qualidade | Bruta | Limpa e validada | Métricas de negócio |
| Schema | Flexível | Estável/contrato | Otimizado p/ consumo |
| Escrita | Append-only | Upsert/overwrite | Overwrite/refresh |
| Formato | Original/Parquet | Parquet/Iceberg | Parquet/Iceberg/Redshift |
| Quem lê | Engenharia de dados | Analistas, engenharia, ML | BI, ML, APIs |
| Particionamento | Por ingestão | Por tempo/chave de negócio | Por consumo |

---

## 6. Mapeando para S3 + Glue + Catálogo

Estrutura de **buckets/prefixos** (uma boa organização física):

```
s3://datalake-dev-treinamento/
├── bronze/
│   ├── vendas/        (dt_ingestao=2026-07-01/...)
│   ├── clientes/
│   └── produtos/
├── prata/
│   ├── vendas/        (ano=2026/mes=07/...)
│   ├── clientes/
│   └── produtos/
└── ouro/
    ├── vendas_regiao_mes/
    └── top_clientes/
```

No **Glue Data Catalog**, crie **um banco por camada** (ex.: `datalake_bronze`, `datalake_prata`, `datalake_ouro`) ou um banco só com tabelas prefixadas (`vendas_bronze`, `vendas_prata`, `vendas_ouro`). Crawlers populam os metadados.

Cada camada tem **um job Glue** próprio (`bronze_ingest.py`, `silver_transform.py`, `gold_aggregate.py` na pasta `glue-jobs/`). Orquestre a sequência com **Step Functions** ou **Glue Workflows**.

---

## 7. Governança por camada

- **Bronze:** acesso restrito a engenharia de dados (dados crus podem conter PII).
- **Prata:** acesso a analistas/engenharia via **Lake Formation** (linha/coluna).
- **Ouro:** acesso amplo a BI e consumidores de negócio.

Criptografia em todas. Tags de custo por camada. Auditoria via CloudTrail + Lake Formation.

---

## 8. Padrão avançado: Bronze em Iceberg

Quando a Bronze precisa de **upsert** (mesma entidade atualizada pela fonte), Parquet append-only obriga regras de dedup pesadas na Prata. Uma variante é usar **Iceberg na Bronze** com `MERGE` — você mantém histórico e atualiza in-place, simplificando a Prata. Avalie o trade-off (complexidade × flexibilidade).

---

## Exercícios do módulo

**Ex. 1 — Defina as camadas:** Para um cenário de RH (funcionários, salários, férias), proponha o que entra em Bronze, Prata e Ouro. Quais agregações de negócio fariam sentido no Ouro?

**Ex. 2 — Bronze append-only:** Implemente `bronze_ingest.py` com as colunas `ingestao_ts`, `arquivo_origem` e `batch_id`. Rode duas vezes com o mesmo arquivo — ele deve aparecer **duas vezes** (é append; a dedup vem na Prata).

**Ex. 3 — Prata estável:** No `silver_transform.py`, garanta `dropDuplicates(["id_venda"])` para que reprocessar a Bronze não duplique a Prata.

**Ex. 4 — Ouro para dashboard:** Crie um Ouro `vendas_regiao_mes` (script `gold_aggregate.py`). Consulte no Athena e monte um gráfico no QuickSight.

**Ex. 5 — Pergunta:** Por que **não** recomendaríamos já agregar tudo no Ouro e pular a Prata? ¹

¹ *Porque a Prata é a **fonte de verdade corporativa**, limpa e enriquecida, de onde TODOS os Ouros derivam. Pular a Prata faria cada dashboard reprocessar a Bronze (lento, caro, inconsistente) e duplicar a lógica de limpeza em cada Ouro — qualquer correção teria que ser replicada em N lugares. A Prata isola e reaproveita o trabalho.*
