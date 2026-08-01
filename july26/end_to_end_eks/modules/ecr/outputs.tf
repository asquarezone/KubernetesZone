output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
output "name" { value = aws_ecr_repository.this.name }
# The registry host, which is what you docker login against.
output "registry_id" { value = aws_ecr_repository.this.registry_id }
