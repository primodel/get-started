locals {
  labels = merge({ "app_kubernetes_io_name" = "primodel", "managed-by" = "terraform" }, var.labels)
}

resource "random_password" "db" {
  length  = 32
  special = false # URL-safe for PRIMODEL_DATABASE_URL
}

# ── Cloud SQL (PostgreSQL, private IP) ──────────────────────────────────────────────────────────
resource "google_sql_database_instance" "this" {
  name                = "${var.name}-pg"
  project             = var.project_id
  region              = var.region
  database_version    = var.db_version
  deletion_protection = var.db_deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = var.db_availability_type
    user_labels       = local.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
  }
}

resource "google_sql_database" "this" {
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "this" {
  name     = var.db_username
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  password = random_password.db.result
}

# ── Object store: GCS + a service account with an HMAC key (S3-compatible interop) ──────────────
resource "google_storage_bucket" "this" {
  name                        = var.bucket_name
  project                     = var.project_id
  location                    = var.bucket_location
  uniform_bucket_level_access = true
  labels                      = local.labels

  versioning {
    enabled = true
  }
}

resource "google_service_account" "store" {
  account_id   = "${var.name}-store"
  project      = var.project_id
  display_name = "Primodel object store"
}

resource "google_storage_bucket_iam_member" "store" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.store.email}"
}

resource "google_storage_hmac_key" "this" {
  project               = var.project_id
  service_account_email = google_service_account.store.email
}
