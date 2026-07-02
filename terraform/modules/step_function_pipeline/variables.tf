variable "name_prefix" {
  description = "Prefixo de nomes (ex.: dev-treinamento)."
  type        = string
}

variable "bronze_job_name" {
  description = "Nome do job Glue da Bronze."
  type        = string
}

variable "silver_job_name" {
  description = "Nome do job Glue da Prata."
  type        = string
}

variable "gold_job_name" {
  description = "Nome do job Glue do Ouro."
  type        = string
}

variable "glue_job_arns" {
  description = "ARNs dos jobs Glue que o Step Functions pode iniciar."
  type        = list(string)
}

variable "glue_job_role_arn" {
  description = "ARN da role usada pelos jobs Glue (para iam:PassRole)."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}

variable "enable_logging" {
  description = "Habilita logs de execução no CloudWatch Logs."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retenção dos logs (dias)."
  type        = number
  default     = 30
}

variable "enable_schedule" {
  description = "Habilita agendamento EventBridge (cron)."
  type        = bool
  default     = false
}

variable "schedule_expression" {
  description = "Expressão de agendamento (EventBridge). Ex.: 'cron(0 2 * * ? *)' = diário às 02h."
  type        = string
  default     = "cron(0 2 * * ? *)"
}
