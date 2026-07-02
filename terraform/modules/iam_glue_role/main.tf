###############################################################################
# Módulo: iam_glue_role
# Cria uma role IAM para o AWS Glue com least-privilege:
#  - Confiança no serviço glue.amazonaws.com
#  - Permissões básicas do serviço (managed policy AWSGlueServiceRole)
#  - Política inline para ler/gravar apenas nos buckets informados + logs
###############################################################################

# Trust policy: só o serviço do Glue pode assumir esta role.
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "GlueAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.ambiente}-${var.nome_base}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# Managed policy da AWS com as permissões de serviço do Glue (Catálogo, métricas etc.)
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Política de logs no CloudWatch (necessária para vermos os logs do job).
resource "aws_iam_role_policy" "logs" {
  name = "${var.ambiente}-${var.nome_base}-glue-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# Política de acesso aos buckets do data lake (least-privilege por bucket).
data "aws_iam_policy_document" "s3_access" {
  # Permite listar os buckets
  statement {
    sid    = "ListBuckets"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = var.bucket_arns
  }

  # Permite ler/gravar OBJETOS nesses buckets
  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    # ARN dos objetos = ARN do bucket + "/*"
    resources = [for arn in var.bucket_arns : "${arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${var.ambiente}-${var.nome_base}-glue-s3"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.s3_access.json
}
