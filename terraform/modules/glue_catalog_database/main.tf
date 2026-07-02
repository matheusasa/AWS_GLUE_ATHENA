###############################################################################
# Módulo: glue_catalog_database
# Cria um banco no Glue Data Catalog (metadados das tabelas) e, opcionalmente,
# Crawlers para descobrir schema de pastas no S3 e popular o Catálogo.
###############################################################################

# 1) Banco de dados (catálogo) do Glue
resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = coalesce(var.description, "Banco do Catálogo Glue - ${var.database_name}")

  # LF tags (Lake Formation) opcionais para governança por etiqueta
  dynamic "lf_tags" {
    for_each = length(var.lf_tags) > 0 ? [1] : []
    content {
      key   = lf_tags.value.key
      value = lf_tags.value.value
    }
  }

  tags = var.tags
}

# 2) Crawlers opcionais: para cada item de var.crawlers, cria um crawler.
#    Cada crawler aponta para um caminho S3 e cria tabelas neste banco.
resource "aws_glue_crawler" "this" {
  for_each = var.crawlers

  name          = "${var.database_name}-${each.key}"
  database_name = aws_glue_catalog_database.this.name
  role          = var.crawler_role_arn
  description   = lookup(each.value, "description", "Crawler para ${each.key}")

  # Esquema de detecção de schema
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
    Grouping = { TableGroupingPolicy = "CombineCompatibleSchemas" }
  })

  # Agendamento opcional (ex.: "cron(0 1 * * ? *)" para diário às 01h)
  schedule = lookup(each.value, "schedule", null)

  s3_target {
    s3_path = each.value.s3_path
  }

  # Quando há tabelas Iceberg/Parquet, classificar corretamente
  dynamic "iceberg_target" {
    for_each = lookup(each.value, "is_iceberg", false) ? [1] : []
    content {
      paths = [each.value.s3_path]
    }
  }

  tags = var.tags

  depends_on = [aws_glue_catalog_database.this]
}
