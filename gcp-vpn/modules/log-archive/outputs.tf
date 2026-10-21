output "bucket_name" {
  description = "Archive bucket."
  value       = google_storage_bucket.archive.name
}

output "sink_name" {
  description = "Cloud Logging sink writing to the bucket."
  value       = google_logging_project_sink.archive.name
}

output "sink_writer_identity" {
  description = "Service identity the sink writes as."
  value       = google_logging_project_sink.archive.writer_identity
}
