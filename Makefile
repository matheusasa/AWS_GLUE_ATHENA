# Makefile com atalhos úteis para o treinamento.
# Uso: make <alvo>   (ex.: make tf-plan-dev)

TF_DIR_DEV  := terraform/envs/dev
TF_DIR_PROD := terraform/envs/prod

.PHONY: help tf-fmt tf-init-dev tf-init-prod tf-plan-dev tf-plan-prod tf-apply-dev tf-apply-prod tf-destroy-dev tf-lint

help: ## Mostra esta ajuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

tf-fmt: ## Formata todos os arquivos .tf
	@echo ">> Formatando Terraform..."
	terraform fmt -recursive terraform/

tf-init-dev: ## Inicializa o backend do ambiente dev
	cd $(TF_DIR_DEV) && terraform init

tf-init-prod: ## Inicializa o backend do ambiente prod
	cd $(TF_DIR_PROD) && terraform init

tf-plan-dev: ## Mostra o plano de execução para dev
	cd $(TF_DIR_DEV) && terraform plan

tf-plan-prod: ## Mostra o plano de execução para prod
	cd $(TF_DIR_PROD) && terraform plan

tf-apply-dev: ## Aplica a infraestrutura em dev
	cd $(TF_DIR_DEV) && terraform apply

tf-apply-prod: ## Aplica a infraestrutura em prod (cuidado!)
	cd $(TF_DIR_PROD) && terraform apply

tf-destroy-dev: ## Destroi toda a infraestrutura de dev (libera custos)
	cd $(TF_DIR_DEV) && terraform destroy

tf-lint: ## Roda tfsec/tflint se instalados
	@command -v tfsec >/dev/null 2>&1 && tfsec terraform/ || echo "tfsec não instalado, pulando"
	@command -v tflint >/dev/null 2>&1 && tflint --chdir=terraform/ || echo "tflint não instalado, pulando"
