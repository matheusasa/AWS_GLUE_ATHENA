###############################################################################
# Outputs do módulo s3_data_lake
###############################################################################

output "bucket_ids" {
  description = "Mapa camada => nome (id) do bucket."
  value       = { for c, b in aws_s3_bucket.this : c => b.id }
}

output "bucket_arns" {
  description = "Mapa camada => ARN do bucket."
  value       = { for c, b in aws_s3_bucket.this : c => b.arn }
}

output "bronze_bucket" {
  description = "Nome do bucket da camada Bronze."
  value       = try(aws_s3_bucket.this["bronze"].id, null)
}

output "prata_bucket" {
  description = "Nome do bucket da camada Prata."
  value       = try(aws_s3_bucket.this["prata"].id, null)
}

output "ouro_bucket" {
  description = "Nome do bucket da camada Ouro."
  value       = try(aws_s3_bucket.this["ouro"].id, null)
}
