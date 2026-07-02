output "workgroup_name" {
  description = "Nome do workgroup criado."
  value       = aws_athena_workgroup.this.name
}

output "workgroup_arn" {
  description = "ARN do workgroup."
  value       = aws_athena_workgroup.this.arn
}
