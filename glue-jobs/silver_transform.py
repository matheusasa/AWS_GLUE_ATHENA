"""
silver_transform.py
Job da camada PRATA.

Objetivo: ler a Bronze (vendas + clientes + produtos), aplicar limpeza e
enriquecimento, e gravar uma tabela "limpa, tipada e enriquecida" na Prata:
  1. Cast de tipos (valor, data).
  2. Padronização (trim, nomes).
  3. Deduplicação por id_venda (mantém o mais recente por ingestao_ts).
  4. Broadcast joins com dimensões (clientes, produtos) — tabelas pequenas.
  5. Coluna calculada valor_total.
  6. Coluna is_valid (qualidade).
  7. Escrita em Parquet particionado por ano/mês (idempotente via overwrite).

Referência: Módulos 05 (intermediário) e 06 (otimizações), 07 (medalhão).
"""

import glue_utils

from pyspark.sql.functions import (
    col, when, to_date, year, month, trim, broadcast,
    sum as _sum, count, round as _round,
)
from pyspark.sql.window import Window
from pyspark.sql.functions import row_number


def main():
    args, spark, glue_ctx, job = glue_utils.init_job(
        required_args=["BRONZE_DB", "SILVER_PATH"]
    )
    log = glue_utils.get_logger(glue_ctx)

    bronze_db = args["BRONZE_DB"]
    silver_path = args["SILVER_PATH"]

    # ------------------------------------------------------------------ #
    # 1) Leitura da Bronze (via Catálogo do Glue)
    # ------------------------------------------------------------------ #
    df_vendas   = spark.table(f"{bronze_db}.vendas")
    df_clientes = spark.table(f"{bronze_db}.clientes")
    df_produtos = spark.table(f"{bronze_db}.produtos")

    log.info(f"[PRATA] Bronze vendas: {df_vendas.count()} linhas")

    # ------------------------------------------------------------------ #
    # 2) Limpeza e tipagem (contrato da Prata)
    # ------------------------------------------------------------------ #
    df = (df_vendas
            # garante tipos corretos
            .withColumn("valor_unit", col("valor_unit").cast("double"))
            .withColumn("quantidade", col("quantidade").cast("int"))
            .withColumn("data_venda", col("data_venda").cast("timestamp"))
            .withColumn("dt", to_date(col("data_venda")))
            .withColumn("canal", trim(col("canal"))))

    # ------------------------------------------------------------------ #
    # 3) Deduplicação: mantém o registro mais recente por id_venda
    # ------------------------------------------------------------------ #
    w = Window.partitionBy("id_venda").orderBy(col("ingestao_ts").desc())
    df = (df.withColumn("rn", row_number().over(w))
            .filter(col("rn") == 1)
            .drop("rn"))

    # ------------------------------------------------------------------ #
    # 4) Enriquecimento: joins com dimensões (broadcast = sem shuffle)
    # ------------------------------------------------------------------ #
    df_clientes_l = df_clientes.select(
        col("id_cliente"),
        col("nome").alias("cliente_nome"),
        col("regiao").alias("cliente_regiao"),
    )
    df_produtos_l = df_produtos.select(
        col("id_produto"),
        col("categoria").alias("produto_categoria"),
        col("marca").alias("produto_marca"),
    )

    df = (df.join(broadcast(df_clientes_l), "id_cliente", "left")
            .join(broadcast(df_produtos_l), "id_produto", "left"))

    # ------------------------------------------------------------------ #
    # 5) Colunas calculadas e qualidade
    # ------------------------------------------------------------------ #
    df = (df.withColumn("valor_total", col("valor_unit") * col("quantidade"))
            .withColumn("ano", year(col("dt")))
            .withColumn("mes", month(col("dt")))
            .withColumn("cliente_regiao", when(col("cliente_regiao").isNull(),
                                               "NAO_INFORMADO").otherwise(col("cliente_regiao")))
            .withColumn("produto_categoria", when(col("produto_categoria").isNull(),
                                                  "SEM_CATEGORIA").otherwise(col("produto_categoria")))
            .withColumn("is_valid",
                        (col("valor_total") > 0)
                        & col("id_cliente").isNotNull()
                        & col("dt").isNotNull()))

    # ------------------------------------------------------------------ #
    # 6) Escrita: Parquet particionado por ano/mês.
    #    overwrite garante idempotência ao reprocessar um mês (Módulo 07).
    #    Nota: para upsert real, considere Iceberg (Módulo 06).
    # ------------------------------------------------------------------ #
    log.info(f"[PRATA] Gravando em {silver_path}")
    colunas_finais = [
        "id_venda", "id_cliente", "id_produto", "data_venda", "dt", "canal",
        "cliente_nome", "cliente_regiao", "produto_categoria", "produto_marca",
        "quantidade", "valor_unit", "valor_total", "is_valid", "ano", "mes",
        "ingestao_ts",
    ]
    glue_utils.write_parquet_partitioned(
        df.select(*colunas_finais),
        path=silver_path,
        partition_cols=["ano", "mes"],
        mode="overwrite",
        num_files=10,
    )

    # Métrica de qualidade (visível no CloudWatch/Job metrics)
    invalidas = df.filter(~col("is_valid")).count()
    log.info(f"[PRATA] Linhas inválidas (is_valid=false): {invalidas}")

    glue_utils.finish_job(job)


if __name__ == "__main__":
    main()
