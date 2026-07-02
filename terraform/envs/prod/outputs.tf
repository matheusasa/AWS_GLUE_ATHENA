output "buckets" {
  value = module.data_lake.bucket_ids
}

output "glue_jobs" {
  value = module.glue_jobs.job_names
}

output "catalog_databases" {
  value = {
    bronze = module.catalog_bronze.database_name
    prata  = module.catalog_prata.database_name
    ouro   = module.catalog_ouro.database_name
  }
}
