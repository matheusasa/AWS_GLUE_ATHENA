"""
bronze_ingest.py
Job da camada BRONZE.

Objetivo: ler os dados crus (CSV) da área de landing e gravar em Parquet
na Bronze, SEM alterar o conteúdo — apenas adicionando colunas de controle:
  - ingestao_ts    : quando o job rodou
  - arquivo_origem : de qual arquivo S3 a linha veio
  - batch_id       : identificador do lote (data/hora de execução)

A Bronze é APPEND-ONLY: nunca alteramos o histórico (Módulo 07).
"""

import glue_utils  # disponível via --extra-py-files

from pyspark.sql.functions import current_timestamp, input_file_name, lit, date_format


def main():
    args, spark, glue_ctx, job = glue_utils.init_job(
        required_args=["INPUT_PATH", "OUTPUT_PATH", "TABLE"]
    )
    log = glue_utils.get_logger(glue_ctx)

    input_path = args["INPUT_PATH"]
    output_path = args["OUTPUT_PATH"]
    table = args["TABLE"]

    log.info(f"[BRONZE] Lendo CSV de {input_path}")

    # Lemos como texto puro para NÃO impor restrições; a Bronze tolera sujeira.
    df = (spark.read
            .option("header", True)
            .option("inferSchema", True)   # Bronze tolera; a Prata tipará com rigor
            .csv(input_path))

    total_in = df.count()
    log.info(f"[BRONZE] Linhas lidas: {total_in}")

    # Colunas de controle. batch_id = timestamp de execução.
    batch_id = date_format(current_timestamp(), "yyyyMMddHHmmss")
    df = (df
            .withColumn("ingestao_ts", current_timestamp())
            .withColumn("arquivo_origem", input_file_name())
            .withColumn("batch_id", batch_id)
            .withColumn("dt_ingestao", date_format(current_timestamp(), "yyyy-MM-dd")))

    log.info(f"[BRONZE] Gravando Parquet em {output_path}")
    # Append-only, particionado por data de ingestão (prune em consultas).
    glue_utils.write_parquet_partitioned(
        df,
        path=output_path,
        partition_cols=["dt_ingestao"],
        mode="append",
        num_files=20,
    )

    log.info(f"[BRONZE] Concluído: {total_in} linhas para tabela '{table}'.")
    glue_utils.finish_job(job)


if __name__ == "__main__":
    main()
