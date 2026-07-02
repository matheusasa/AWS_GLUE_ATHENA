variable "name_prefix" {
  description = "Prefixo do nome dos jobs (ex.: dev-treinamento)."
  type        = string
}

variable "role_arn" {
  description = "ARN da role IAM que os jobs assumirão."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos jobs."
  type        = map(string)
  default     = {}
}

variable "default_glue_version" {
  description = "Versão do Glue usada por padrão."
  type        = string
  default     = "4.0"
}

variable "default_worker_type" {
  description = "Tipo de worker por padrão (G.1X, G.2X, Standard, G.025X)."
  type        = string
  default     = "G.1X"
}

variable "default_number_of_workers" {
  description = "Número de workers por padrão."
  type        = number
  default     = 3
}

variable "spark_ui_logs_path" {
  description = "Caminho S3 para os logs do Spark UI / event logs."
  type        = string
}

variable "default_arguments" {
  description = "Argumentos padrão extras aplicados a todos os jobs."
  type        = map(string)
  default     = {}
}

variable "jobs" {
  description = <<EOT
Mapa de jobs. Chave = nome lógico (vira sufixo do nome do job). Valor:
  script_s3_path    (string)  - caminho s3:// do script .py
  description       (string)  - opcional
  extra_params      (map)     - parâmetros de negócio (--chave=valor)
  extra_py_files    (list)    - s3:// de arquivos .py extras
  default_arguments (map)     - sobrescreve defaults do Glue
  max_retries       (number)  - padrão 0
  timeout           (number)  - minutos, padrão 60
  worker_type       (string)  - sobrescreve default
  number_of_workers (number)  - sobrescreve default
  glue_version      (string)  - sobrescreve default
  enable_bookmark   (bool)    - padrão true
  max_concurrent_runs (number) - execuções concorrentes, padrão 1
EOT
  type = map(object({
    script_s3_path      = string
    description         = optional(string)
    extra_params        = optional(map(string), {})
    extra_py_files      = optional(list(string), [])
    default_arguments   = optional(map(string), {})
    max_retries         = optional(number, 0)
    timeout             = optional(number, 60)
    worker_type         = optional(string)
    number_of_workers   = optional(number)
    glue_version        = optional(string)
    enable_bookmark     = optional(bool, true)
    max_concurrent_runs = optional(number, 1)
  }))
}
