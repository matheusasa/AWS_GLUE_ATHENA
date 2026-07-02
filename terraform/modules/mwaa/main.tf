###############################################################################
# Módulo: mwaa  (Amazon Managed Workflows for Apache Airflow)
# Provisiona um ambiente Airflow GERENCIADO pela AWS para orquestrar os jobs
# Glue via DAG. É um recurso MAIS CARO (cobra por hora enquanto ativo) — use
# só quando quiser de fato explorar o Airflow, e destrua depois.
#
# PRÉ-REQUISITOS (fora deste módulo):
#   - VPC com pelo menos 2 sub-redes em AZs distintas (informe em subnet_ids).
#   - Security group que permita tráfego do MWAA para o S3/Glue.
# O MWAA guarda os DAGs num bucket S3 (criado aqui).
###############################################################################

# 1) Bucket dos DAGs e plugins/requirements do Airflow
resource "aws_s3_bucket" "dags" {
  bucket = "${var.name_prefix}-mwaa-dags-${var.sufixo_unico}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "dags" {
  bucket = aws_s3_bucket.dags.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "dags" {
  bucket                  = aws_s3_bucket.dags.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2) Role de execução do MWAA (acesso ao S3, CloudWatch e Glue)
data "aws_iam_policy_document" "assume_airflow" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["airflow.amazonaws.com", "airflow-env.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-mwaa-exec"
  assume_role_policy = data.aws_iam_policy_document.assume_airflow.json
  tags               = var.tags
}

# Managed policy oficial do MWAA (S3 + CloudWatch + Secrets Manager etc.)
resource "aws_iam_role_policy_attachment" "mwaa" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonMWAAFullApiAccess"
}

# Permissão extra para rodar/ler jobs Glue (AwsGlueJobOperator)
data "aws_iam_policy_document" "glue" {
  statement {
    effect = "Allow"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
      "glue:GetJob",
      "glue:GetJobs",
    ]
    resources = var.glue_job_arns
  }
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.glue_job_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "glue" {
  name   = "${var.name_prefix}-mwaa-glue"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.glue.json
}

# 3) Ambiente MWAA
resource "aws_mwaa_environment" "this" {
  name               = "${var.name_prefix}-airflow"
  airflow_version    = var.airflow_version
  execution_role_arn = aws_iam_role.this.arn

  source_bucket_arn    = aws_s3_bucket.dags.arn
  dag_s3_path          = "dags/"
  requirements_s3_path = "requirements.txt"

  network_configuration {
    security_group_ids = var.security_group_ids
    subnet_ids         = var.subnet_ids
  }

  environment_variables = {
    MWAA__GLUE_JOBS = join(",", var.glue_job_names)
  }

  webserver_access_mode = "PUBLIC_ONLY" # troque por PRIVATE com VPC em prod

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  tags = var.tags
}
