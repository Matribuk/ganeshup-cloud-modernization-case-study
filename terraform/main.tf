#0==========================================================================0
# 0 - Config for AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ca-central-1"
}
variable "db_host" {
  description = "PostgreSQL hostname injected into DATABASE_URL"
  type        = string
  default     = "localhost"
}
#0==========================================================================0

#1==========================================================================1
# 1 - AMAZON S3: Stateless Storage + Public Access Block + 30d Lifecycle
  resource "aws_s3_bucket" "app_storage" {
    bucket = "ganeshup-prod-storage"
  }

  #-> Block all access (access only via Presigned URLs)
  resource "aws_s3_bucket_public_access_block" "app_storage_private" {
    bucket                  = aws_s3_bucket.app_storage.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
  #-|

  #-> Following the Ganeshup JWT_REFRESH_EXPIRES_IN (30d)
  resource "aws_s3_bucket_lifecycle_configuration" "storage_lifecycle" {
    bucket = aws_s3_bucket.app_storage.id

    rule {
      id     = "purge-expired-course-uploads-30d"
      status = "Enabled"
      filter { prefix = "uploads/" }
      expiration { days = 30 }
    }
  }
  #-|
#1==========================================================================1


#2==========================================================================2
# 2 - AWS SECRETS MANAGER: Replace the .env file
  resource "aws_secretsmanager_secret" "backend_env" {
    name        = "prod/ganeshup/backend-env"
    description = "Production secrets migrated from VPS .env file"
  }

  resource "aws_secretsmanager_secret_version" "backend_env_val" {
    secret_id = aws_secretsmanager_secret.backend_env.id
    secret_string = jsonencode({
      DATABASE_URL   = "postgresql://ganeshup_user:local_rds_password@${var.db_host}:5432/ganeshup_db"
      JWT_SECRET     = "kms-managed-jwt-secret"
      API_KEY        = "kms-managed-api-key"
      ADMIN_TOKEN    = "kms-managed-admin-token"
      ENCRYPTION_KEY = "kms-managed-encryption-key"
      OWNER_TOKEN    = "kms-managed-owner-token"
      S3_BUCKET_NAME = aws_s3_bucket.app_storage.id
    })
  }
#2==========================================================================2

#3==========================================================================3
# 3 - EVENTBRIDGE, LAMBDA : Replace the cronjob cleanup API call
  data "archive_file" "cleanup_zip" {
    type        = "zip"
    source_file = "${path.module}/cleanup_worker.py"
    output_path = "${path.module}/cleanup_worker.zip"
  }

  resource "aws_iam_role" "cleanup_lambda_role" {
    name = "ganeshup_cleanup_lambda_role"
    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }]
    })
  }

  #-> Autorise Lambda to write logs into CloudWatch
  resource "aws_iam_role_policy_attachment" "lambda_logs" {
    role       = aws_iam_role.cleanup_lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  }
  #-|

  resource "aws_lambda_function" "token_cleanup" {
    filename         = data.archive_file.cleanup_zip.output_path
    function_name    = "ganeshup-nightly-token-cleanup"
    role             = aws_iam_role.cleanup_lambda_role.arn
    handler          = "cleanup_worker.handler"
    source_code_hash = data.archive_file.cleanup_zip.output_base64sha256
    runtime          = "python3.12"
    timeout          = 30
  }

  resource "aws_cloudwatch_event_rule" "nightly_cleanup" {
    name                = "ganeshup-nightly-cleanup-rule"
    schedule_expression = "cron(0 0 * * ? *)"
  }

  resource "aws_cloudwatch_event_target" "trigger_lambda" {
    rule      = aws_cloudwatch_event_rule.nightly_cleanup.name
    target_id = "GaneshupCleanupLambda"
    arn       = aws_lambda_function.token_cleanup.arn
  }

  resource "aws_lambda_permission" "allow_eventbridge" {
    statement_id  = "AllowExecutionFromEventBridge"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.token_cleanup.function_name
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.nightly_cleanup.arn
  }
#3===========================================================================3