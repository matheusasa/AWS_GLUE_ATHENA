output "database_name" {
  description = "Nome do banco criado."
  value       = aws_glue_catalog_database.this.name
}

output "crawler_names" {
  description = "Nomes dos crawlers criados (se houver)."
  value       = { for k, c in aws_glue_crawler.this : k => c.name }
}
