###############################################################################
# Outputs do ambiente DEV
###############################################################################

output "buckets" {
  description = "Buckets criados por camada."
  value       = module.data_lake.bucket_ids
}

output "glue_role_arn" {
  description = "ARN da role do Glue."
  value       = module.glue_role.role_arn
}

output "glue_jobs" {
  description = "Nomes dos jobs criados."
  value       = module.glue_jobs.job_names
}

output "catalog_databases" {
  description = "Bancos do Catálogo criados."
  value = {
    bronze = module.catalog_bronze.database_name
    prata  = module.catalog_prata.database_name
    ouro   = module.catalog_ouro.database_name
  }
}

output "athena_workgroup" {
  description = "Workgroup do Athena para consultas."
  value       = module.athena.workgroup_name
}
