"""
glue_utils.py
Funções utilitárias compartilhadas pelos jobs do treinamento.

Este arquivo é enviado ao S3 e referenciado pelos jobs via
--extra-py-files. Centraliza o que se repete em todos os jobs:
  - leitura de argumentos,
  - inicialização do GlueContext/Spark,
  - schemas reutilizáveis,
  - escrita particionada com boa prática de tamanho de arquivo,
  - logging estruturado.
"""

import sys
from typing import Dict

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField, IntegerType, StringType, DoubleType, TimestampType,
)
from awsglue.context import GlueContext
from awsglue.job import Job


# --------------------------------------------------------------------------- #
# Schemas
# --------------------------------------------------------------------------- #
SCHEMA_VENDAS = StructType([
    StructField("id_venda",    IntegerType(),  nullable=False),
    StructField("id_cliente",  IntegerType(),  nullable=True),
    StructField("id_produto",  IntegerType(),  nullable=True),
    StructField("quantidade",  IntegerType(),  nullable=True),
    StructField("valor_unit",  DoubleType(),   nullable=True),
    StructField("data_venda",  TimestampType(), nullable=True),
    StructField("canal",       StringType(),   nullable=True),
])

SCHEMA_CLIENTES = StructType([
    StructField("id_cliente", IntegerType(), nullable=False),
    StructField("nome",       StringType(),  nullable=True),
    StructField("regiao",     StringType(),  nullable=True),
])

SCHEMA_PRODUTOS = StructType([
    StructField("id_produto", IntegerType(), nullable=False),
    StructField("categoria",  StringType(),  nullable=True),
    StructField("marca",      StringType(),  nullable=True),
])


# --------------------------------------------------------------------------- #
# Argumentos
# --------------------------------------------------------------------------- #
def get_args(required: list) -> Dict[str, str]:
    """
    Lê os argumentos obrigatórios passados ao job.
    Lança erro claro se algum estiver faltando.
    """
    return getResolvedOptions(sys.argv, ["JOB_NAME"] + required)


# --------------------------------------------------------------------------- #
# Inicialização
# --------------------------------------------------------------------------- #
def init_job(required_args: list):
    """
    Inicializa SparkContext, GlueContext, SparkSession e Job.
    Retorna (args, spark, glueContext, job) para o job usar.
    """
    args = get_args(required_args)

    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session

    # Otimizações (Módulo 06): AQE liga coalesce de partições e corrige skew.
    spark.conf.set("spark.sql.adaptive.enabled", "true")
    spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
    spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")

    job = Job(glueContext)
    job.init(args["JOB_NAME"], args)
    return args, spark, glueContext, job


def finish_job(job: Job):
    """Encerra o job (persiste bookmark e métricas)."""
    job.commit()


# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
def get_logger(glueContext: GlueContext):
    return glueContext.get_logger()


# --------------------------------------------------------------------------- #
# Escrita particionada (boa prática de tamanho de arquivo)
# --------------------------------------------------------------------------- #
def write_parquet_partitioned(df, path: str, partition_cols: list[str],
                              mode: str = "append", num_files: int = 20):
    """
    Grava DataFrame em Parquet particionado, controlando o nº de arquivos
    por partição (evita o 'small files problem' - Módulo 06).

    Usa repartitionByRange para agrupar registros similares e reduzir shuffles.
    """
    writer = df.repartitionByRange(num_files, *partition_cols).write
    (writer
        .mode(mode)
        .format("parquet")
        .option("compression", "snappy")
        .partitionBy(*partition_cols)
        .save(path))
