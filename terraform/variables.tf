variable "aws_region" {
  description = "AWS region where resources will be provisioned"
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository_name" {
  description = "ECR repository name for the API"
  type        = string
  default     = "gitops-api"
}

variable "ecr_image_retention_count" {
  description = "Maximum number of images retained in ECR before expiring older ones (Lifecycle Policy)"
  type        = number
  default     = 10
}

variable "github_oidc_sub" {
  description = "GitHub Actions OIDC 'sub' claim to allow federated authentication without static keys"
  type        = string
  default     = "repo:mdhenriques@103260127/gitops-lab@1416272098:ref:refs/heads/master"
}

variable "ssm_db_connection_param_name" {
  description = "SSM Parameter Store parameter name storing the database connection string"
  type        = string
  default     = "gitops-db-connection"
}
