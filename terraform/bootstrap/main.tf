# ==========================================
# BOOTSTRAP: Terraform State S3 Bucket
# ==========================================
# Stack separated from ../main.tf to solve the "chicken and egg" problem:
# the bucket storing the main stack state cannot be managed by that same state.
#
# This stack uses LOCAL state (terraform.tfstate, ignored by .gitignore). It contains
# no secrets and is responsible for declaratively provisioning the S3 bucket with
# strict security policies (SSE-S3, TLS Deny, Versioning, Lifecycle).
#
# If you want to reuse an existing S3 bucket in AWS, import it once with:
#   terraform import aws_s3_bucket.terraform_state <bucket-name>
#
# Execution order (one-time operation):
#   1. cd terraform/bootstrap && terraform init && terraform apply
#      (creates the S3 bucket with complete hardening)
#   2. cd ../ && terraform init && terraform apply
#      (provisions main resources using remote S3 backend)

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

  # Protects against "terraform destroy" / accidental deletion of bucket holding all state.
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

# Server-side encryption explicitly declared (SSE-S3).
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access (public ACLs and policies).
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs: bucket owner is always object owner.
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Enforce TLS for all bucket access.
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

  # Prevent race conditions with concurrent policy operations on the same bucket.
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# Retain state version history, but not indefinitely.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  # Lifecycle configuration requires versioning already enabled.
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
  description = "Bucket used by S3 remote backend in main stack"
}
