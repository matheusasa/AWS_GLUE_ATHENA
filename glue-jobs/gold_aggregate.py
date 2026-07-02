"""
gold_aggregate.py
Job da camada OURO.

Objetivo: ler a Prata e produzir uma tabela agregada pronta para consumo
(dashboards/BI). Aqui: vendas por região x categoria x ano x mês, com
receita, qtd de vendas e ticket médio.

O Ouro é modelado para um caso de consumo específico (Módulo 07).
Mudou a pergunta de negócio? Crie outro Ouro — a Prata permanece estável.
"""

import glue_utils

from pyspark.sql.functions import col, sum as _sum, count, round as _round, max as _max


def main():
    args, spark, glue_ctx, job = glue_utils.init_job(
        required_args=["SILVER_DB", "GOLD_PATH"]
    )
    log = glue_utils.get_logger(glue_ctx)

    silver_db = args["SILVER_DB"]
    gold_path = args["GOLD_PATH"]

    # ------------------------------------------------------------------ #
    # 1) Leitura da Prata (só linhas válidas)
    # ------------------------------------------------------------------ #
    df = spark.table(f"{silver_db}.vendas").filter(col("is_valid") == True)
    log.info(f"[OURO] Linhas lidas da Prata (válidas): {df.count()}")

    # ------------------------------------------------------------------ #
    # 2) Agregação de negócio
    # ------------------------------------------------------------------ #
    ouro = (df
            .groupBy("cliente_regiao", "produto_categoria", "ano", "mes")
            .agg(
                _sum("valor_total").alias("receita"),
                count("id_venda").alias("qtd_vendas"),
                _round(_sum("valor_total") / count("id_venda"), 2).alias("ticket_medio"),
                _max("data_venda").alias("ultima_venda"),
            ))

    # ------------------------------------------------------------------ #
    # 3) Escrita particionada por ano/mês (overwrite -> refresh do dashboard)
    # ------------------------------------------------------------------ #
    log.info(f"[OURO] Gravando em {gold_path}")
    glue_utils.write_parquet_partitioned(
        ouro,
        path=gold_path,
        partition_cols=["ano", "mes"],
        mode="overwrite",
        num_files=5,   # Ouro costuma ser pequeno; poucos arquivos bastam
    )

    log.info(f"[OURO] Concluído.")
    glue_utils.finish_job(job)


if __name__ == "__main__":
    main()
