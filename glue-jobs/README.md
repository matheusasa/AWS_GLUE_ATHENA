# glue-jobs — Scripts PySpark para AWS Glue

Scripts que implementam as três camadas do data lake na **arquitetura
medalhão**. São enviados ao S3 automaticamente pelo Terraform (módulo
`glue_job`) e referenciados pelos jobs.

```
glue-jobs/
├── bronze_ingest.py      CSV cru -> Parquet Bronze (+ metadados)
├── silver_transform.py   Bronze  -> Prata (limpeza, joins, dedup)
├── gold_aggregate.py     Prata   -> Ouro (agregado p/ consumo)
└── common/
    └── glue_utils.py     Utilitários compartilhados (extra-py-files)
```

## Parâmetros de cada job (passados pelo Terraform)

| Job | Parâmetros |
|---|---|
| `bronze_ingest` | `INPUT_PATH`, `OUTPUT_PATH`, `TABLE` |
| `silver_transform` | `BRONZE_DB`, `SILVER_PATH` |
| `gold_aggregate` | `SILVER_DB`, `GOLD_PATH` |

Esses parâmetros viram `--INPUT_PATH=...` no Glue e são lidos por
`getResolvedOptions` (em `glue_utils.init_job`).

## O que cada script faz

**`bronze_ingest.py`** — Lê o CSV da landing, adiciona `ingestao_ts`,
`arquivo_origem` e `batch_id`, e grava Parquet particionado por `dt_ingestao`
em modo **append** (a Bronze nunca altera o histórico).

**`silver_transform.py`** — Lê Bronze (vendas + clientes + produtos via
Catálogo), faz cast de tipos, **deduplica por `id_venda`** (mantém o mais
recente), faz **broadcast join** com as dimensões, calcula `valor_total`,
marca `is_valid` e grava Prata particionada por `ano`/`mes` (overwrite =
idempotente ao reprocessar).

**`gold_aggregate.py`** — Lê a Prata válida, agrega por
`cliente_regiao × produto_categoria × ano × mes` (`receita`, `qtd_vendas`,
`ticket_medio`), grava o Ouro particionado por `ano`/`mes`.

## Boas práticas aplicadas (referência aos docs)

- **AQE** ligado em `glue_utils` (coalesce de partições + skew join) — Módulo 06.
- **broadcast** nos joins com dimensões pequenas — Módulo 05/06.
- **repartitionByRange** na escrita para evitar *small files* — Módulo 06.
- **`is_valid`** + contagem de inválidas para qualidade — Módulo 09.
- **Idempotência** na Prata/Ouro (`overwrite` por partição; p/ upsert real, Iceberg).

## Ordem de execução

```
bronze_ingest  ->  silver_transform  ->  gold_aggregate  ->  crawler  ->  Athena
```

## Testando localmente (opcional)

Para desenvolver sem gastar no Glue, instale o PySpark localmente e adapte a
entrada do job (substitua `init_job` por uma sessão Spark local). Para testes
fiéis, use o **AWS Glue local dev** (`gluepyspark` / Docker do Glue) com os
dados de `data/sample/`.

```bash
# Exemplo rápido com pyspark local (apenas para lógica):
pip install pyspark==3.3.*   # mesma versão do Glue 4.0
```

> Os scripts só rodam de verdade dentro do Glue (dependem de `awsglue.*`).
> Para lógica pura (transformações), abstraia para funções testáveis e
# importe-as tanto no job quanto em testes locais.
