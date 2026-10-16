terraform {
  # >= 1.11: necessario para atributos write-only (value_wo) e recursos ephemeral
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7" # 3.7+ para ephemeral "random_password"
    }
  }

  backend "s3" {
    bucket       = "gitops-tfstate-murilo-lab"
    key          = "devsecops/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ==========================================
# GESTÃO DE SEGREDOS (SSM & External Secrets)
# ==========================================

# Recurso ephemeral: o valor existe so durante o plan/apply e NUNCA e gravado no
# state nem no plano.
ephemeral "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_connection" {
  name        = var.ssm_db_connection_param_name
  description = "Connection string para o banco de dados da API GitOps"
  type        = "SecureString"

  # Write-only: enviado a AWS mas nao persistido no state. O valor so e reenviado
  # quando value_wo_version muda. Incremente-o para rotacionar a senha.
  value_wo         = ephemeral.random_password.db_password.result
  value_wo_version = 1
}

# Criação do Usuário IAM para o External Secrets Operator
resource "aws_iam_user" "eso_user" {
  name = "external-secrets-operator-svc"
}

# Geração das Credenciais de Acesso (Access Key e Secret Key)
resource "aws_iam_access_key" "eso_user_key" {
  user = aws_iam_user.eso_user.name
}

# Aplicação do Princípio do Menor Privilégio (Least Privilege)
resource "aws_iam_policy" "eso_policy" {
  name        = "ExternalSecretsOperatorPolicy"
  description = "Leitura restrita ao parametro do banco de dados e pull de imagens do ECR (token gerado pelo ESO)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = aws_ssm_parameter.db_connection.arn
      },
      {
        # Usado pelo ClusterGenerator ECRAuthorizationToken (k8s/base) para manter
        # o imagePullSecret ecr-cred renovado.
        Sid      = "EcrGetAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # A AWS nao aceita ARN especifico para esta acao
      },
      {
        # O token herda as permissoes do usuario: somente pull, somente neste repo.
        Sid    = "EcrPullOnlyApiRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.api_repo.arn
      }
    ]
  })
}

# Anexar a Política de segurança ao usuário
resource "aws_iam_user_policy_attachment" "eso_attach" {
  user       = aws_iam_user.eso_user.name
  policy_arn = aws_iam_policy.eso_policy.arn
}

# ==========================================
# AMAZON ECR (Repositório de Imagens)
# ==========================================

resource "aws_ecr_repository" "api_repo" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Politica de ciclo de vida do ECR: retem apenas as imagens mais recentes para otimizacao de custos
resource "aws_ecr_lifecycle_policy" "api_repo" {
  repository = aws_ecr_repository.api_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "FinOps: mantem apenas as ultimas ${var.ecr_image_retention_count} imagens no repositorio"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ==========================================
# GITHUB ACTIONS OIDC & IAM ROLE (CI/CD)
# ==========================================

# 1. Provedor de Identidade OIDC do GitHub
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # Thumbprints oficiais do GitHub Actions validados
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# 2. IAM Role assumida pelo GitHub Actions
resource "aws_iam_role" "github_actions_deploy" {
  name = "GitHubActionsDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = var.github_oidc_sub
          }
        }
      }
    ]
  })
}

# 3. Política de Permissão para Push de Imagens no ECR (Least Privilege)
resource "aws_iam_policy" "ecr_push_policy" {
  name        = "GitHubActionsECRPushPolicy"
  description = "Permite que o GitHub Actions faca autenticacao e push de imagens no ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # Exigência da AWS: GetAuthorizationToken não aceita ARN específico
      },
      {
        Sid    = "AllowPushPullOnRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        # Restrito estritamente ao repositório gitops-api
        Resource = aws_ecr_repository.api_repo.arn
      }
    ]
  })
}

# 4. Anexar a Política do ECR à Role do GitHub Actions
resource "aws_iam_role_policy_attachment" "github_actions_ecr_attach" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.ecr_push_policy.arn
}

# ==========================================
# OUTPUTS
# ==========================================

output "eso_access_key_id" {
  value       = aws_iam_access_key.eso_user_key.id
  description = "Chave de Acesso para o aws-secret-store.yaml"
}

output "eso_secret_access_key" {
  value       = aws_iam_access_key.eso_user_key.secret
  description = "Chave Secreta para o aws-secret-store.yaml"
  sensitive   = true
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.api_repo.repository_url
  description = "URL do repositorio para fazer o push da imagem"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_deploy.arn
  description = "ARN da Role para usar no arquivo deploy.yaml do GitHub Actions"
}