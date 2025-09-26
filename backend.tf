#############################################################
# S3 BUCKET FOR TERRAFORM STATE
# Stores the remote state file
#############################################################

resource "aws_s3_bucket" "terraform_state" {
  bucket        = "backend-for-terraform-state"
  force_destroy = true
}

#############################################################
# ENABLE VERSIONING ON S3 BUCKET
# Keeps multiple versions of the state file (useful for rollback)
#############################################################

resource "aws_s3_bucket_versioning" "terraform_bucket_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

#############################################################
# ENABLE SERVER-SIDE ENCRYPTION
# Encrypts Terraform state files in S3 at rest
#############################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_crypto_conf" {
  bucket = aws_s3_bucket.terraform_state.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#############################################################
# DYNAMODB TABLE FOR STATE LOCKING
# Prevents concurrent 'terraform apply' operations
#############################################################

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

