###############################################################################
# Módulo: s3_data_lake
# Cria um conjunto de buckets S3 (um por camada da arquitetura medalhão),
# com versionamento, criptografia, bloqueio de acesso público e lifecycle.
#
# Demonstração do padrão for_each: um bloco de recurso cria N buckets,
# um para cada camada (bronze, prata, ouro).
###############################################################################

# 1) Buckets (um por camada). Nomes globais => incluímos sufixo único.
resource "aws_s3_bucket" "this" {
  for_each = toset(var.camadas)

  # Ex.: dev-treinamento-dados-bronze-abc123
  bucket = "${var.ambiente}-${var.nome_base}-${each.key}-${var.sufixo_unico}"

  tags = merge(
    { Camada = each.key },
    var.tags,
  )
}

# 2) Versionamento (recuperação contra deleção/sobrescrita)
resource "aws_s3_bucket_versioning" "this" {
  for_each = toset(var.camadas)

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# 3) Criptografia em repouso (SSE-S3 AES256). Para auditoria de chave,
# troque por aws_s3_bucket_server_side_encryption_configuration com kms.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = toset(var.camadas)

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4) Bloqueio de acesso público (NUNCA exponha um data lake)
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = toset(var.camadas)

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5) Lifecycle: transição para IA/Glacier + expiração (por camada).
# Bronze guarda mais tempo e vai para Glacier; Ouro fica "quente".
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for c in var.camadas : c => c if var.enable_lifecycle }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "lifecycle-${each.key}"
    status = "Enabled"

    # Aplica a TODOS os objetos do bucket.
    filter {}

    dynamic "transition" {
      for_each = var.lifecycle_transition_days.ia != null ? [1] : []
      content {
        days          = var.lifecycle_transition_days.ia
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.lifecycle_transition_days.glacier != null ? [1] : []
      content {
        days          = var.lifecycle_transition_days.glacier
        storage_class = "GLACIER"
      }
    }

    expiration {
      days = var.lifecycle_expiration_days
    }

    # Evita custo acumulado de versões antigas (importante com versionamento on)
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# 6) Política de "nega owned buckets ACLs" /ownership (recomendado v5)
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = toset(var.camadas)

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
