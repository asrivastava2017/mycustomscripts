# Usage:
#   make bootstrap ENV=gstore-non-prod   # once per environment: state bucket + backend.hcl
#   make plan      ENV=gstore-non-prod
#   make apply     ENV=gstore-non-prod
ENV ?= gstore-non-prod
ENV_DIR := environments/$(ENV)

.PHONY: bootstrap init plan apply destroy fmt validate output

bootstrap:
	terraform -chdir=bootstrap init -reconfigure -backend-config=path=../$(ENV_DIR)/bootstrap.tfstate
	terraform -chdir=bootstrap apply -compact-warnings -var-file=../$(ENV_DIR)/terraform.tfvars -var environment=$(ENV)

init:
	terraform init -reconfigure -backend-config=$(ENV_DIR)/backend.hcl

plan: init
	terraform plan -var-file=$(ENV_DIR)/terraform.tfvars -out=$(ENV).tfplan

apply:
	terraform apply $(ENV).tfplan

destroy: init
	terraform destroy -var-file=$(ENV_DIR)/terraform.tfvars

fmt:
	terraform fmt -recursive

validate:
	terraform init -backend=false && terraform validate
	terraform -chdir=bootstrap init -backend=false && terraform -chdir=bootstrap validate

output:
	terraform output
