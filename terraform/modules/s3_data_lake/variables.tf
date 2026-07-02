###############################################################################
# Variáveis do módulo s3_data_lake
###############################################################################

variable "nome_base" {
  description = "Nome base do projeto (ex.: treinamento). Usado no nome dos buckets."
  type        = string
}

variable "ambiente" {
  description = "Ambiente (ex.: dev, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "hml", "prod"], var.ambiente)
    error_message = "ambiente deve ser dev, hml ou prod."
  }
}

variable "camadas" {
  description = "Lista de camadas (uma por bucket). Padrão: bronze, prata, ouro."
  type        = list(string)
  default     = ["bronze", "prata", "ouro"]
}

variable "sufixo_unico" {
  description = "Sufixo único (números/letras) porque nomes de bucket são globais na AWS."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas a todos os buckets."
  type        = map(string)
  default     = {}
}

variable "enable_lifecycle" {
  description = "Habilita regras de lifecycle (IA/Glacier/expiração)."
  type        = bool
  default     = true
}

variable "lifecycle_transition_days" {
  description = "Dias para transição de storage class. null = não transiciona."
  type = object({
    ia      = number
    glacier = number
  })
  default = {
    ia      = 90
    glacier = 365
  }
}

variable "lifecycle_expiration_days" {
  description = "Dias para expirar objetos. 0 = não expira."
  type        = number
  default     = 2555 # ~7 anos
}
