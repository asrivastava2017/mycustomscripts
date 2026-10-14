# Remote state location for this environment. The bucket must already exist
# (versioning on), e.g.:
#   gcloud storage buckets create gs://REPLACE-WITH-STATE-BUCKET --location=asia-south1 --uniform-bucket-level-access
#   gcloud storage buckets update gs://REPLACE-WITH-STATE-BUCKET --versioning
bucket = "REPLACE-WITH-STATE-BUCKET"
prefix = "pritunl/gstore-non-prod"
