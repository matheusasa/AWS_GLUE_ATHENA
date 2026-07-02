variable "name_prefix" {
  description = "Prefixo do nome do workgroup (ex.: dev-treinamento)."
  type        = string
}

variable "results_bucket" {
  description = "Nome do bucket S3 onde o Athena guardará os resultados das consultas."
  type        = string
}

variable "description" {
  description = "Descrição do workgroup."
  type        = string
  default     = null
}

variable "enabled" {
  description = "Se true, workgroup fica ENABLED."
  type        = bool
  default     = true
}

variable "requester_pays" {
  description = "Habilita requester pays para buckets externos."
  type        = bool
  default     = false
}

variable "bytes_scanned_cutoff_per_query" {
  description = "Limite de bytes por consulta (controle de custo). null = sem limite."
  type        = number
  default     = 10737418240 # 10 GB
}

variable "tags" {
  description = "Tags do workgroup."
  type        = map(string)
  default     = {}
}
