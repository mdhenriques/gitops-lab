variable "aws_region" {
  description = "Regiao da AWS onde os recursos serao provisionados"
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository_name" {
  description = "Nome do repositorio ECR para a API"
  type        = string
  default     = "gitops-api"
}

variable "ecr_image_retention_count" {
  description = "Quantidade maxima de imagens mantidas no ECR antes de expirar as antigas (Lifecycle Policy)"
  type        = number
  default     = 10
}

variable "github_oidc_sub" {
  description = "Claim 'sub' do GitHub Actions OIDC para permitir autenticacao federada sem chaves fixas"
  type        = string
  default     = "repo:mdhenriques@103260127/gitops-lab@1416272098:ref:refs/heads/master"
}

variable "ssm_db_connection_param_name" {
  description = "Nome do parametro SSM Parameter Store que armazena a conexao do banco de dados"
  type        = string
  default     = "gitops-db-connection"
}
