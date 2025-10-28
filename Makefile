# Default listing targets
list: ## List all available make targets
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

boottf: ## Bootstrap Azure environment and Terraform backend
	@echo "Bootstrapping Azure environment and Terraform backend..."
	@pwsh ./initialiseß.ps1
	@echo "Bootstrap completed."
