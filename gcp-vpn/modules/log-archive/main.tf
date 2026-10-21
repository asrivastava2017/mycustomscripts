# Long-term archive of selected Cloud Logging entries in a Cloud Storage bucket.
# The sink writes hourly JSON batches to gs://<bucket>/<log name>/YYYY/MM/DD/...;
# lifecycle rules move them to Coldline and delete them after the retention period.

resource "google_storage_bucket" "archive" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false # never delete archived logs with the bucket
  labels                      = merge(var.labels, { purpose = "log-archive" })

  dynamic "lifecycle_rule" {
    for_each = var.coldline_after_days > 0 && var.coldline_after_days < var.retention_days ? [1] : []
    content {
      condition {
        age = var.coldline_after_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_logging_project_sink" "archive" {
  project                = var.project_id
  name                   = "${var.name}-log-archive"
  description            = "Archives Pritunl logs to gs://${google_storage_bucket.archive.name}"
  destination            = "storage.googleapis.com/${google_storage_bucket.archive.name}"
  filter                 = var.log_filter
  unique_writer_identity = true
}

# The sink writes as its own service identity; it may only create objects in this bucket.
resource "google_storage_bucket_iam_member" "sink_writer" {
  bucket = google_storage_bucket.archive.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.archive.writer_identity
}
