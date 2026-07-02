output "job_names" {
  description = "Mapa nome lógico => nome do job no Glue."
  value       = { for k, j in aws_glue_job.this : k => j.name }
}

output "job_arns" {
  description = "Mapa nome lógico => ARN do job."
  value       = { for k, j in aws_glue_job.this : k => j.arn }
}
