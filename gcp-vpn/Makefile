# Usage: make plan ENV=gstore-non-prod
ENV ?= gstore-non-prod
ENV_DIR := environments/$(ENV)

.PHONY: init plan apply destroy fmt validate output

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

output:
	terraform output
