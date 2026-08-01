terraform {
  required_version = ">= 1.9.0"

  # -------------------------------------------------------------------------
  # Remote state. Run ./scripts/bootstrap-backend.sh FIRST, then paste the
  # printed bucket name below (it is globally unique per student).
  #
  # LOCKING: this uses S3 native locking (use_lockfile), which needs
  # Terraform >= 1.10 and NO DynamoDB table. If you are pinned to an older
  # Terraform, delete use_lockfile and add:
  #     dynamodb_table = "tf-lock-ekstore"
  # ...and uncomment the table in scripts/bootstrap-backend.sh.
  #
  # AUTHENTICATION: the S3 backend uses the same credential chain as the AWS
  # provider - environment variables, then ~/.aws/credentials, then the
  # instance/EKS role. There is no separate "data plane" login the way Azure
  # storage has, but you DO need s3:GetObject/PutObject/DeleteObject on the
  # bucket and s3:ListBucket on the bucket itself.
  #
  # For a purely local lab run you may comment this whole block out.
  # -------------------------------------------------------------------------
  backend "s3" {
    bucket       = "REPLACE_ME_WITH_YOUR_BUCKET"
    key          = "eks-store/dev.terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
