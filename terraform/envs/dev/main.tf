###############################################################################
# Ambiente: DEV
# Monta um Data Lake completo (medalhão) usando os módulos do projeto:
#   - Buckets S3 por camada (bronze/prata/ouro)        -> s3_data_lake
#   - Role IAM do Glue                                  -> iam_glue_role
#   - Catálogo Glue + Crawlers                          -> glue_catalog_database
#   - Jobs Glue (bronze_ingest, silver_transform, gold) -> glue_job
#   - Athena (consulta SQL)                             -> athena_workgroup
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto (S3 + DynamoDB para lock). Edite com SEU bucket de estado.
  backend "s3" {
    bucket         = "tf-state-treinamento-123" # <-- TROQUE pelo seu bucket de estado
    key            = "datalake/dev/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
  }

  # Observação: o backend é declarado aqui e NÃO pode usar variáveis.
  # Por isso o nome do bucket de estado é "hardcoded".
}

provider "aws" {
  region = var.regiao

  default_tags {
    tags = local.tags_comuns
  }
}

# ---------------------------------------------------------------------------
# Locais e data sources
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.ambiente}-${var.projeto}"

  tags_comuns = {
    Projeto     = var.projeto
    Ambiente    = var.ambiente
    Gerenciado  = "terraform"
    CentroCusto = var.centro_custo
  }

  # Os três buckets do data lake (gerados pelo módulo s3_data_lake)
  # precisam estar acessíveis à role do Glue.
}

# ---------------------------------------------------------------------------
# 1) Data Lake (buckets por camada)
# ---------------------------------------------------------------------------
module "data_lake" {
  source = "../../modules/s3_data_lake"

  nome_base    = var.projeto
  ambiente     = var.ambiente
  camadas      = ["bronze", "prata", "ouro"]
  sufixo_unico = var.sufixo_unico
  tags         = local.tags_comuns

  # Em dev, podemos deixar lifecycle mais agressivo (economia)
  enable_lifecycle = true
  lifecycle_transition_days = {
    ia      = 30
    glacier = 90
  }
  lifecycle_expiration_days = 365
}

# ---------------------------------------------------------------------------
# 2) Role do Glue (least-privilege para os buckets do lake)
# ---------------------------------------------------------------------------
module "glue_role" {
  source = "../../modules/iam_glue_role"

  nome_base   = var.projeto
  ambiente    = var.ambiente
  bucket_arns = values(module.data_lake.bucket_arns)
  tags        = local.tags_comuns
}

# ---------------------------------------------------------------------------
# 3) Catálogo Glue (um banco por camada) + Crawlers
# ---------------------------------------------------------------------------
module "catalog_bronze" {
  source = "../../modules/glue_catalog_database"

  database_name    = "${var.projeto}_bronze"
  crawler_role_arn = module.glue_role.role_arn
  tags             = local.tags_comuns

  crawlers = {
    vendas   = { s3_path = "s3://${module.data_lake.bronze_bucket}/vendas/" }
    clientes = { s3_path = "s3://${module.data_lake.bronze_bucket}/clientes/" }
    produtos = { s3_path = "s3://${module.data_lake.bronze_bucket}/produtos/" }
  }
}

module "catalog_prata" {
  source = "../../modules/glue_catalog_database"

  database_name    = "${var.projeto}_prata"
  crawler_role_arn = module.glue_role.role_arn
  tags             = local.tags_comuns

  crawlers = {
    vendas = { s3_path = "s3://${module.data_lake.prata_bucket}/vendas/" }
  }
}

module "catalog_ouro" {
  source = "../../modules/glue_catalog_database"

  database_name    = "${var.projeto}_ouro"
  crawler_role_arn = module.glue_role.role_arn
  tags             = local.tags_comuns

  crawlers = {
    vendas_regiao_mes = { s3_path = "s3://${module.data_lake.ouro_bucket}/vendas_regiao_mes/" }
  }
}

# ---------------------------------------------------------------------------
# 4) Upload dos scripts PySpark para o S3 (pasta scripts/ no bucket bronze)
#    O job aponta para s3://.../scripts/<nome>.py
# ---------------------------------------------------------------------------
locals {
  scripts_prefix = "scripts"
  script_files = {
    bronze_ingest    = "../../../glue-jobs/bronze_ingest.py"
    silver_transform = "../../../glue-jobs/silver_transform.py"
    gold_aggregate   = "../../../glue-jobs/gold_aggregate.py"
    glue_utils       = "../../../glue-jobs/common/glue_utils.py"
  }
}

resource "aws_s3_object" "scripts" {
  for_each = local.script_files

  bucket = module.data_lake.bronze_bucket
  key    = "${local.scripts_prefix}/${each.key}.py"
  source = each.value

  # Re-envia quando o conteúdo mudar (etag = hash do arquivo)
  etag = filemd5(each.value)
}

# ---------------------------------------------------------------------------
# 5) Jobs Glue
# ---------------------------------------------------------------------------
module "glue_jobs" {
  source = "../../modules/glue_job"

  name_prefix               = local.name_prefix
  role_arn                  = module.glue_role.role_arn
  tags                      = local.tags_comuns
  spark_ui_logs_path        = "s3://${module.data_lake.bronze_bucket}/spark-logs/"
  default_worker_type       = "G.1X"
  default_number_of_workers = 3

  jobs = {
    bronze_ingest = {
      description    = "Ingestão Bronze: CSV cru -> Parquet com metadados de controle."
      script_s3_path = "s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/bronze_ingest.py"
      extra_py_files = ["s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/glue_utils.py"]
      extra_params = {
        INPUT_PATH  = "s3://${module.data_lake.bronze_bucket}/landing/vendas/"
        OUTPUT_PATH = "s3://${module.data_lake.bronze_bucket}/vendas/"
        TABLE       = "vendas"
      }
      timeout = 30
    }
    silver_transform = {
      description    = "Transformação Prata: limpeza, joins e dedup."
      script_s3_path = "s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/silver_transform.py"
      extra_py_files = ["s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/glue_utils.py"]
      extra_params = {
        BRONZE_DB   = module.catalog_bronze.database_name
        SILVER_PATH = "s3://${module.data_lake.prata_bucket}/vendas/"
      }
      timeout = 30
    }
    gold_aggregate = {
      description    = "Agregação Ouro: vendas por região/mês."
      script_s3_path = "s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/gold_aggregate.py"
      extra_py_files = ["s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/glue_utils.py"]
      extra_params = {
        SILVER_DB = module.catalog_prata.database_name
        GOLD_PATH = "s3://${module.data_lake.ouro_bucket}/vendas_regiao_mes/"
      }
      timeout = 20
    }
  }

  depends_on = [aws_s3_object.scripts]
}

# ---------------------------------------------------------------------------
# 6) Athena (consulta SQL sobre o Catálogo)
# ---------------------------------------------------------------------------
module "athena" {
  source = "../../modules/athena_workgroup"

  name_prefix    = local.name_prefix
  results_bucket = module.data_lake.ouro_bucket
  tags           = local.tags_comuns

  # Em dev: limite de 10 GB por consulta (evita acidentes de custo)
  bytes_scanned_cutoff_per_query = 10737418240
}

# ---------------------------------------------------------------------------
# 7) Orquestração (Step Functions): bronze -> prata -> ouro
#    Em dev o agendamento fica OFF (disparo manual para testes).
# ---------------------------------------------------------------------------
module "pipeline" {
  source = "../../modules/step_function_pipeline"

  name_prefix       = local.name_prefix
  bronze_job_name   = module.glue_jobs.job_names["bronze_ingest"]
  silver_job_name   = module.glue_jobs.job_names["silver_transform"]
  gold_job_name     = module.glue_jobs.job_names["gold_aggregate"]
  glue_job_arns     = values(module.glue_jobs.job_arns)
  glue_job_role_arn = module.glue_role.role_arn
  tags              = local.tags_comuns

  enable_logging  = true
  enable_schedule = false # dev: manual; em prod fica true
}
