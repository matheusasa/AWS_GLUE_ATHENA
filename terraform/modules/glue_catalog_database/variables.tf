variable "database_name" {
  description = "Nome do banco no Glue Data Catalog."
  type        = string
}

variable "description" {
  description = "Descrição do banco. Default: gerada automaticamente."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags aplicadas ao banco e aos crawlers."
  type        = map(string)
  default     = {}
}

variable "lf_tags" {
  description = "LF-Tags do Lake Formation para o banco (lista de {key,value})."
  type = list(object({
    key   = string
    value = string
  }))
  default = []
}

variable "crawler_role_arn" {
  description = "ARN da role que os crawlers usarão (normalmente a role do Glue)."
  type        = string
  default     = null
}

variable "crawlers" {
  description = <<EOT
Mapa de crawlers opcionais. Chave = nome lógico. Valor = objeto com:
  s3_path     (string)  - caminho S3 a varrer (ex.: s3://bucket/bronze/vendas/)
  schedule    (string)  - opcional, expressão cron EventBridge
  is_iceberg  (bool)    - opcional, usa iceberg_target
  description (string)  - opcional
EOT
  type = map(object({
    s3_path     = string
    schedule    = optional(string)
    is_iceberg  = optional(bool, false)
    description = optional(string)
  }))
  default = {}
}
