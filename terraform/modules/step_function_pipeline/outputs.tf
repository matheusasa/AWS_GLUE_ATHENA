output "state_machine_arn" {
  description = "ARN da máquina de estados."
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "Nome da máquina de estados."
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "ARN da role do Step Functions."
  value       = aws_iam_role.this.arn
}

output "schedule_name" {
  description = "Nome do agendamento (se habilitado)."
  value       = var.enable_schedule ? aws_scheduler_schedule.this[0].name : null
}
