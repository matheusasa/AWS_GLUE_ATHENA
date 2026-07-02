output "environment_arn" {
  value = aws_mwaa_environment.this.arn
}

output "environment_name" {
  value = aws_mwaa_environment.this.name
}

output "dags_bucket" {
  value = aws_s3_bucket.dags.id
}

output "webserver_url" {
  value = aws_mwaa_environment.this.webserver_url
}
