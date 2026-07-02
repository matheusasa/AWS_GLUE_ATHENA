output "role_arn" {
  description = "ARN da role criada para o Glue."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nome da role criada para o Glue."
  value       = aws_iam_role.this.name
}
