###############################################################################
# Variáveis do ambiente DEV
###############################################################################

variable "regiao" {
  description = "Região AWS."
  type        = string
  default     = "sa-east-1"
}

variable "ambiente" {
  description = "Nome do ambiente."
  type        = string
  default     = "dev"
}

variable "projeto" {
  description = "Nome base do projeto (usado em buckets, roles, jobs)."
  type        = string
  default     = "treinamento"
}

variable "centro_custo" {
  description = "Centro de custo para tags (controle financeiro)."
  type        = string
  default     = "CC-1001"
}

variable "sufixo_unico" {
  description = <<EOT
Sufixo único de 4-8 caracteres (sem hifens) para garantir nomes globais
de bucket. Use algo como suas iniciais + números. Ex.: "abc123".
EOT
  type        = string
}
