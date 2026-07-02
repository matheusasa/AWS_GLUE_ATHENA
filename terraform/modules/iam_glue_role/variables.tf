variable "nome_base" {
  description = "Nome base do projeto (usado no nome da role)."
  type        = string
}

variable "ambiente" {
  description = "Ambiente (dev, hml, prod)."
  type        = string
}

variable "bucket_arns" {
  description = "Lista de ARNs dos buckets que a role do Glue poderá acessar."
  type        = list(string)
}

variable "tags" {
  description = "Tags aplicadas à role."
  type        = map(string)
  default     = {}
}
