###############################################################################
# Ambiente: PROD
# Mesma topologia do dev, porém com ajustes de produção:
#   - Mais workers / tipo maior (G.2X) para SLA
#   - Lifecycle mais longo (retenção de 7 anos)
#   - Crawlers agendados (não manuais)
#   - Athena sem limite agressivo, mas com budget control externamente
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "tf-state-treinamento-123" # <-- TROQUE pelo seu bucket de estado
    key            = "datalake/prod/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.regiao
  default_tags {
    tags = local.tags_comuns
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.ambiente}-${var.projeto}"
  tags_comuns = {
    Projeto     = var.projeto
    Ambiente    = var.ambiente
    Gerenciado  = "terraform"
    CentroCusto = var.centro_custo
  }
  scripts_prefix = "scripts"
}

# 1) Data Lake
module "data_lake" {
  source = "../../modules/s3_data_lake"

  nome_base    = var.projeto
  ambiente     = var.ambiente
  camadas      = ["bronze", "prata", "ouro"]
  sufixo_unico = var.sufixo_unico
  tags         = local.tags_comuns

  # Em prod: retenção longa, IA após 180 dias, Glacier após 1 ano
  enable_lifecycle = true
  lifecycle_transition_days = {
    ia      = 180
    glacier = 365
  }
  lifecycle_expiration_days = 2555 # ~7 anos (conforme política)
}

# 2) Role do Glue
module "glue_role" {
  source      = "../../modules/iam_glue_role"
  nome_base   = var.projeto
  ambiente    = var.ambiente
  bucket_arns = values(module.data_lake.bucket_arns)
  tags        = local.tags_comuns
}

# 3) Catálogos + crawlers AGENDADOS (cron diário)
module "catalog_bronze" {
  source           = "../../modules/glue_catalog_database"
  database_name    = "${var.projeto}_bronze"
  crawler_role_arn = module.glue_role.role_arn
  tags             = local.tags_comuns
  crawlers = {
    vendas   = { s3_path = "s3://${module.data_lake.bronze_bucket}/vendas/", schedule = "cron(0 2 * * ? *)" }
    clientes = { s3_path = "s3://${module.data_lake.bronze_bucket}/clientes/", schedule = "cron(0 2 * * ? *)" }
    produtos = { s3_path = "s3://${module.data_lake.bronze_bucket}/produtos/", schedule = "cron(0 2 * * ? *)" }
  }
}

module "catalog_prata" {
  source           = "../../modules/glue_catalog_database"
  database_name    = "${var.projeto}_prata"
  crawler_role_arn = module.glue_role.role_arn
  tags             = local.tags_comuns
  crawlers = {
    vendas = { s3_path = "s3://${module.data_lake.prata_bucket}/vendas/", schedule = "cron(0 3 * * ? *)" }
  }
}

module "catalog_ouro" {
  source           = "../../modules/glue_catalog_database"
  database_name    = "${var.projeto}_ouro"
  crawler_role_arn = module.glue_role.role_arn
  tags             = local.tags_comuns
  crawlers = {
    vendas_regiao_mes = { s3_path = "s3://${module.data_lake.ouro_bucket}/vendas_regiao_mes/", schedule = "cron(0 4 * * ? *)" }
  }
}

# 4) Upload dos scripts
locals {
  script_files = {
    bronze_ingest    = "../../../glue-jobs/bronze_ingest.py"
    silver_transform = "../../../glue-jobs/silver_transform.py"
    gold_aggregate   = "../../../glue-jobs/gold_aggregate.py"
    glue_utils       = "../../../glue-jobs/common/glue_utils.py"
  }
}

resource "aws_s3_object" "scripts" {
  for_each = local.script_files
  bucket   = module.data_lake.bronze_bucket
  key      = "${local.scripts_prefix}/${each.key}.py"
  source   = each.value
  etag     = filemd5(each.value)
}

# 5) Jobs - mais recursos em prod
module "glue_jobs" {
  source                    = "../../modules/glue_job"
  name_prefix               = local.name_prefix
  role_arn                  = module.glue_role.role_arn
  tags                      = local.tags_comuns
  spark_ui_logs_path        = "s3://${module.data_lake.bronze_bucket}/spark-logs/"
  default_worker_type       = "G.2X"
  default_number_of_workers = 10
  jobs = {
    bronze_ingest = {
      description    = "Ingestão Bronze (prod)."
      script_s3_path = "s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/bronze_ingest.py"
      extra_py_files = ["s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/glue_utils.py"]
      max_retries    = 2
      timeout        = 60
      extra_params = {
        INPUT_PATH  = "s3://${module.data_lake.bronze_bucket}/landing/vendas/"
        OUTPUT_PATH = "s3://${module.data_lake.bronze_bucket}/vendas/"
        TABLE       = "vendas"
      }
    }
    silver_transform = {
      description    = "Transformação Prata (prod)."
      script_s3_path = "s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/silver_transform.py"
      extra_py_files = ["s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/glue_utils.py"]
      max_retries    = 2
      timeout        = 90
      extra_params = {
        BRONZE_DB   = module.catalog_bronze.database_name
        SILVER_PATH = "s3://${module.data_lake.prata_bucket}/vendas/"
      }
    }
    gold_aggregate = {
      description    = "Agregação Ouro (prod)."
      script_s3_path = "s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/gold_aggregate.py"
      extra_py_files = ["s3://${module.data_lake.bronze_bucket}/${local.scripts_prefix}/glue_utils.py"]
      max_retries    = 1
      timeout        = 60
      extra_params = {
        SILVER_DB = module.catalog_prata.database_name
        GOLD_PATH = "s3://${module.data_lake.ouro_bucket}/vendas_regiao_mes/"
      }
    }
  }
  depends_on = [aws_s3_object.scripts]
}

# 6) Athena
module "athena" {
  source         = "../../modules/athena_workgroup"
  name_prefix    = local.name_prefix
  results_bucket = module.data_lake.ouro_bucket
  tags           = local.tags_comuns
}

# 7) Orquestração (Step Functions): bronze -> prata -> ouro, agendada diariamente
module "pipeline" {
  source = "../../modules/step_function_pipeline"

  name_prefix       = local.name_prefix
  bronze_job_name   = module.glue_jobs.job_names["bronze_ingest"]
  silver_job_name   = module.glue_jobs.job_names["silver_transform"]
  gold_job_name     = module.glue_jobs.job_names["gold_aggregate"]
  glue_job_arns     = values(module.glue_jobs.job_arns)
  glue_job_role_arn = module.glue_role.role_arn
  tags              = local.tags_comuns

  enable_logging      = true
  enable_schedule     = true
  schedule_expression = "cron(0 2 * * ? *)" # diário às 02h
}
