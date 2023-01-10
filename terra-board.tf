resource "google_project_service" "cloudrun" {
  project = var.project
  service = "run.googleapis.com"
}

resource "google_service_account" "tensorboard_sa" {
  project     = var.project
  account_id  = "tensorboard-sa"
  description = "Service account for serverless tensorboard instance"
}

resource "google_project_iam_member" "tensorboard_iam" {
  for_each = toset(var.tensorboard_iam_roles)
  role     = each.key
  project  = var.project
  member   = "serviceAccount:${google_service_account.tensorboard_sa.email}"
}

variable "tensorboard_iam_roles" {
  description = "IAM roles to bind on service account"
  type        = list(string)
  default = [
    "roles/storage.admin"
  ]
}

resource "google_storage_bucket" "tensorboard_logs_bucket" {
  name     = "${var.project}-tensorboard-logs"
  project  = var.project
  location = var.region
}

resource "google_cloud_run_service" "tensorboard" {
  name     = "tensorboard"
  location = var.region

  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "all"
    }
  }

  timeouts {
    create = "10m"
    delete = "10m"
  }

  template {

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "1"
      }
    }

    spec {
      service_account_name = google_service_account.tensorboard_sa.email
      containers {
        image = docker pull aurjay/tensorboard-gcp:firsttry
        resources {
          limits = {
            cpu    = "1.0"
            memory = "3.75G"
          }
        }
        env {
          name  = "LOG_DIR"
          value = "gs://${google_storage_bucket.tensorboard_logs_bucket.name}"
        }
        env {
          name  = "LOAD_FAST"
          value = "false"
        }
      }
    }
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.tensorboard.location
  project  = google_cloud_run_service.tensorboard.project
  service  = google_cloud_run_service.tensorboard.name

  policy_data = data.google_iam_policy.noauth.policy_data
}
