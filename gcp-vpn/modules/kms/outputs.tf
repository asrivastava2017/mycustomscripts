output "key_ring_id" {
  description = "Key ring ID."
  value       = google_kms_key_ring.this.id
}

output "crypto_key_id" {
  description = "Crypto key ID (projects/.../cryptoKeys/...). Usable as kms_key_self_link. Only available once the IAM grants exist, so disks never race them."
  value       = google_kms_crypto_key.this.id
  depends_on  = [google_kms_crypto_key_iam_member.encrypter_decrypter]
}
