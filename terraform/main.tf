terraform {
  backend "s3" {
    bucket       = "gitops-tfstate-murilo-lab" 
    key          = "devsecops/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1" 
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_connection" {
  name        = "gitops-db-connection"
  description = "Connection string para o banco de dados da API GitOps"
  type        = "SecureString"
  value       = random_password.db_password.result
}

# 2. Criação do Usuário IAM para o External Secrets Operator
resource "aws_iam_user" "eso_user" {
  name = "external-secrets-operator-svc"
}

# 3. Geração das Credenciais de Acesso (Access Key e Secret Key)
resource "aws_iam_access_key" "eso_user_key" {
  user = aws_iam_user.eso_user.name
}

# 4. Aplicação do Princípio do Menor Privilégio (Least Privilege)
resource "aws_iam_policy" "eso_policy" {
  name        = "ExternalSecretsOperatorPolicy"
  description = "Permite leitura restrita apenas ao parametro do banco de dados"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        # O acesso é restrito estritamente ao ARN do parâmetro criado acima
        Resource = aws_ssm_parameter.db_connection.arn
      }
    ]
  })
}

# 5. Anexar a Política de segurança ao usuário
resource "aws_iam_user_policy_attachment" "eso_attach" {
  user       = aws_iam_user.eso_user.name
  policy_arn = aws_iam_policy.eso_policy.arn
}

# 6. Outputs para visualizar as chaves geradas e criar o Secret no Kubernetes
output "eso_access_key_id" {
  value       = aws_iam_access_key.eso_user_key.id
  description = "Chave de Acesso para o aws-secret-store.yaml"
}

output "eso_secret_access_key" {
  value       = aws_iam_access_key.eso_user_key.secret
  description = "Chave Secreta para o aws-secret-store.yaml"
  sensitive   = true
}

# 1. Bucket S3 para guardar o arquivo de estado
resource "aws_s3_bucket" "terraform_state" {
  bucket = "gitops-tfstate-murilo-lab" # Altere se der erro de nome duplicado
}

# Habilitar versionamento (salva o histórico da infraestrutura)
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. Tabela DynamoDB para State Locking (impede conflitos e concorrência)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "gitops-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ==========================================
# AMAZON ECR (Repositório de Imagens)
# ==========================================

resource "aws_ecr_repository" "api_repo" {
  name                 = "gitops-api"
  
  # Prática DevSecOps: Impede que alguém sobrescreva uma imagem de produção 
  # enviando um código malicioso com a mesma tag (ex: v1)
  image_tag_mutability = "IMMUTABLE" 

  # Prática DevSecOps: O ECR fará um scan de segurança procurando CVEs 
  # conhecidas assim que a imagem bater na AWS
  image_scanning_configuration {
    scan_on_push = true 
  }
}

# Output para facilitar a nossa vida na hora de fazer o push da imagem
output "ecr_repository_url" {
  value       = aws_ecr_repository.api_repo.repository_url
  description = "URL do repositorio para fazer o push da imagem"
}