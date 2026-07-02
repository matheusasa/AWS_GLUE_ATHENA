###############################################################################
# Módulo: athena_workgroup
# Cria um Workgroup do Athena com bucket de resultados e (opcional) limite de
# dados escaneados por consulta - controle de custo importante em data lakes.
###############################################################################

resource "aws_athena_workgroup" "this" {
  name = "${var.name_prefix}-wg"

  description = coalesce(var.description, "Workgroup Athena - ${var.name_prefix}")

  state = var.enabled ? "ENABLED" : "DISABLED"

  configuration {
    enforce_workgroup_configuration = true # impede o usuário sobrescrever
    publish_workgroup_settings      = true
    requester_pays_enabled          = var.requester_pays

    # Resultado das consultas vai para este bucket
    result_configuration {
      output_location = "s3://${var.results_bucket}/athena/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Controle de custo: limite de bytes por consulta (opcional).
    dynamic "bytes_scanned_cutoff_per_query" {
      for_each = var.bytes_scanned_cutoff_per_query != null ? [1] : []
      content {
        bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff_per_query
      }
    }
  }

  tags = var.tags
}
