###############################################################################
# Módulo: glue_job
# Cria um ou mais jobs do AWS Glue (PySpark) a partir de um mapa `jobs`.
# Demonstração de for_each + coalesce (defaults de módulo podem ser
# sobrescritos por job).
###############################################################################

locals {
  # Argumentos padrão aplicados a TODOS os jobs (podem ser sobrescritos por job)
  default_arguments = merge(
    {
      "--enable-metrics"                   = "true"
      "--enable-continuous-cloudwatch-log" = "true"
      "--enable-spark-ui"                  = "true"
      "--spark-event-logs-path"            = var.spark_ui_logs_path
      "--job-language"                     = "python"
      "--datalake-formats"                 = "iceberg" # habilita Iceberg no Glue 4
    },
    var.default_arguments,
  )
}

resource "aws_glue_job" "this" {
  for_each = var.jobs

  name        = "${var.name_prefix}-${each.key}"
  description = lookup(each.value, "description", "Job Glue: ${each.key}")
  role_arn    = var.role_arn

  # Script PySpark (já no S3). Arquivos .py extras (ex.: common/glue_utils.py)
  # são passados via "--extra-py-files" nos default_arguments abaixo.
  script_location = each.value.script_s3_path

  # Limite de execuções concorrentes do mesmo job.
  execution_property {
    max_concurrent_runs = lookup(each.value, "max_concurrent_runs", 1)
  }

  glue_version = lookup(each.value, "glue_version", var.default_glue_version)
  worker_type  = lookup(each.value, "worker_type", var.default_worker_type)
  number_of_workers = lookup(
    each.value, "number_of_workers", var.default_number_of_workers
  )
  max_retries  = lookup(each.value, "max_retries", 0)
  max_capacity = (lookup(each.value, "worker_type", var.default_worker_type) == "Standard") ? lookup(each.value, "number_of_workers", var.default_number_of_workers) : null

  timeout = lookup(each.value, "timeout", 60)

  # Argumentos: defaults + extras do job + bookmark
  default_arguments = merge(
    local.default_arguments,
    lookup(each.value, "default_arguments", {}),
    # bookmark: enable/pause
    {
      "--job-bookmark-option" = lookup(each.value, "enable_bookmark", true) ? "job-bookmark-enable" : "job-bookmark-disable"
    },
    # parâmetros de negócio (--INPUT_PATH etc.) vão como --chave=valor
    { for k, v in lookup(each.value, "extra_params", {}) : "--${k}" => v },
    # extra py files
    length(lookup(each.value, "extra_py_files", [])) > 0 ? { "--extra-py-files" = join(",", each.value.extra_py_files) } : {},
  )

  tags = merge(var.tags, { Job = each.key })
}