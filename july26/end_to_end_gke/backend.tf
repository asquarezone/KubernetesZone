terraform {
  required_version = ">= 1.9.0"

  # -------------------------------------------------------------------------
  # Remote state. Run ./scripts/bootstrap-backend.sh FIRST, then paste the
  # printed bucket name below (GCS bucket names are globally unique).
  #
  # LOCKING: GCS locking is built in. There is no DynamoDB-equivalent to
  # create and no flag to set - the backend uses object generation numbers.
  # This is the least fiddly of the three clouds' backends.
  #
  # AUTHENTICATION: uses Application Default Credentials, the same chain as
  # the provider. You need roles/storage.objectAdmin on the bucket. Unlike
  # Azure, "can create the bucket" and "can write objects in it" are not
  # split across two planes - but they ARE still separate IAM permissions.
  #
  # For a purely local lab run you may comment this whole block out.
  # -------------------------------------------------------------------------
  backend "gcs" {
    bucket = "REPLACE_ME_WITH_YOUR_BUCKET"
    prefix = "gke-store/dev"
  }
}
