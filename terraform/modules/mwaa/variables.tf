variable "name_prefix" {
  type        = string
  description = "Prefixo de nomes (ex.: dev-treinamento)."
}

variable "sufixo_unico" {
  type        = string
  description = "Sufixo único para o nome do bucket de DAGs."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "airflow_version" {
  type        = string
  default     = "2.10.3"
  description = "Versão do Apache Airflow no MWAA."
}

variable "subnet_ids" {
  type        = list(string)
  description = "2+ IDs de sub-redes em AZs distintas para o MWAA."
}

variable "security_group_ids" {
  type        = list(string)
  description = "IDs de security groups para o MWAA."
}

variable "glue_job_arns" {
  type        = list(string)
  description = "ARNs dos jobs Glue que o Airflow orquestrará."
}

variable "glue_job_names" {
  type        = list(string)
  description = "Nomes dos jobs Glue (passados como variável de ambiente p/ as DAGs)."
}

variable "glue_job_role_arn" {
  type        = string
  description = "ARN da role usada pelos jobs Glue (para iam:PassRole)."
}
