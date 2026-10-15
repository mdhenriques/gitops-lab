# ==========================================
# BOOTSTRAP: bucket S3 do Terraform state
# ==========================================
# Stack separado do ../main.tf para resolver o problema "ovo e galinha": o bucket
# que guarda o state do stack principal nao pode ser gerenciado por esse mesmo state.
#
# Este stack usa state LOCAL (terraform.tfstate, ignorado pelo .gitignore). Ele nao
# contem segredos e e responsavel por provisionar o bucket S3 de forma declarativa
# com politicas estritas de seguranca (SSE-S3, TLS Deny, Versionamento, Lifecycle).
#
# Caso deseje reaproveitar um bucket S3 ja existente na AWS, importe-o uma vez com:
#   terraform import aws_s3_bucket.terraform_state <nome-do-bucket>
#
# Ordem de execucao (uma unica vez):
#   1. cd terraform/bootstrap && terraform init && terraform apply
#      (cria o bucket S3 com o hardening completo)
#   2. cd ../ && terraform init && terraform apply
#      (provisiona os recursos principais com backend S3 remoto)

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  state_bucket_name = "gitops-tfstate-murilo-lab"
}

# ------------------------------------------
# Bucket
# ------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  # Protege contra "terraform destroy"/remocao acidental do bucket com todo o state.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia em repouso declarada explicitamente (SSE-S3).
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Bloqueio total de acesso publico (ACLs e policies publicas).
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Desabilita ACLs: o dono do bucket e sempre o dono dos objetos.
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Exige TLS em qualquer acesso ao bucket.
resource "aws_s3_bucket_policy" "deny_insecure_transport" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Evita conflito de operacoes concorrentes de policy no mesmo bucket.
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# Mantem o historico de versoes do state, mas nao indefinidamente.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  # A configuracao de lifecycle exige versionamento ja habilitado.
  depends_on = [aws_s3_bucket_versioning.terraform_state]

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Bucket usado pelo backend S3 do stack principal"
}
