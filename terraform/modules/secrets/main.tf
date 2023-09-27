resource "google_secret_manager_secret" "secret_key" {
  secret_id = var.secret_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret_key_data" {
  secret = google_secret_manager_secret.secret_key.id
  secret_data = var.secret_data
}