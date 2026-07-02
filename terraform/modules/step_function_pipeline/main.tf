###############################################################################
# Módulo: step_function_pipeline
# Orquestra os 3 jobs Glue (bronze -> prata -> ouro) com AWS Step Functions.
#
# Usa o padrao de integracao ".sync" (glue:startJobRun.sync): o Step Functions
# inicia o job e ESPERA automaticamente o termino, sem precisar de estados
# manuais de Wait/GetJobRun/Choice. Cada estagio tem Retry + Catch.
#
# Inclui tambem (opcional) um agendamento EventBridge Scheduler para rodar no cron.
###############################################################################

# ---------------------------------------------------------------------------
# 1) Role do Step Functions (pode iniciar/consultar os jobs Glue + logs)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_sfn" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_sfn.json
  tags               = var.tags
}

data "aws_iam_policy_document" "sfn_perms" {
  # Iniciar e acompanhar jobs Glue
  statement {
    effect = "Allow"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]
    resources = var.glue_job_arns
  }

  # Passar a role do Glue para o job (StartJobRun exige iam:PassRole na role do job)
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

  # Logs de execucao do Step Functions (quando logging habilitado)
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn_perms" {
  name   = "${var.name_prefix}-sfn-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.sfn_perms.json
}

# ---------------------------------------------------------------------------
# 2) Log group para a execucao da maquina de estados
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/vendedlogs/states/${var.name_prefix}-medalhao"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# 3) Maquina de estados (definition a partir do template ASL)
# ---------------------------------------------------------------------------
locals {
  definition = templatefile(
    "${path.module}/statemachine.asl.json.tpl",
    {
      bronze_job = var.bronze_job_name
      silver_job = var.silver_job_name
      gold_job   = var.gold_job_name
    }
  )
}

resource "aws_sfn_state_machine" "this" {
  name       = "${var.name_prefix}-medalhao"
  role_arn   = aws_iam_role.this.arn
  definition = local.definition

  logging_configuration {
    level                  = var.enable_logging ? "ERROR" : "OFF"
    include_execution_data = var.enable_logging
    log_destination        = var.enable_logging ? "${aws_cloudwatch_log_group.this[0].arn}:*" : null
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 4) Agendamento (EventBridge Scheduler) - opcional
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_scheduler" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "schedule" {
  count              = var.enable_schedule ? 1 : 0
  name               = "${var.name_prefix}-sfn-schedule-role"
  assume_role_policy = data.aws_iam_policy_document.assume_scheduler.json
  tags               = var.tags
}

data "aws_iam_policy_document" "schedule_perms" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.this.arn]
  }
}

resource "aws_iam_role_policy" "schedule_perms" {
  count  = var.enable_schedule ? 1 : 0
  name   = "${var.name_prefix}-sfn-schedule-policy"
  role   = aws_iam_role.schedule[0].id
  policy = data.aws_iam_policy_document.schedule_perms.json
}

resource "aws_scheduler_schedule" "this" {
  count               = var.enable_schedule ? 1 : 0
  name                = "${var.name_prefix}-medalhao-daily"
  description         = "Dispara o pipeline medalhao diariamente."
  state               = "ENABLED"
  schedule_expression = var.schedule_expression
  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.this.arn
    role_arn = aws_iam_role.schedule[0].arn
  }
}
