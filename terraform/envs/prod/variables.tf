variable "regiao" {
  description = "Região AWS."
  type        = string
  default     = "sa-east-1"
}

variable "ambiente" {
  description = "Nome do ambiente."
  type        = string
  default     = "prod"
}

variable "projeto" {
  description = "Nome base do projeto."
  type        = string
  default     = "treinamento"
}

variable "centro_custo" {
  description = "Centro de custo para tags."
  type        = string
  default     = "CC-1001"
}

variable "sufixo_unico" {
  description = "Sufixo único (iniciais + números) para nomes globais de bucket."
  type        = string
}
