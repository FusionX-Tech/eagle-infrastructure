# Keycloak Configuration Makefile
# Provides convenient commands for managing Keycloak setup

# Configuration
KEYCLOAK_URL ?= http://localhost:8080
REALM_NAME ?= eagle-dev
ENVIRONMENT ?= dev
COMPOSE_FILE = docker-compose.keycloak.yml

# Colors for output
BLUE = \033[0;34m
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m # No Color

.PHONY: help setup validate start stop restart logs clean backup restore test

# Default target
help: ## Show this help message
	@echo "$(BLUE)Keycloak Configuration Management$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)Environment variables:$(NC)"
	@echo "  KEYCLOAK_URL    Keycloak URL (default: http://localhost:8080)"
	@echo "  REALM_NAME      Realm name (default: eagle-dev)"
	@echo "  ENVIRONMENT     Environment (default: dev)"

setup: ## Set up Keycloak realm and service accounts (interactive)
	@echo "$(BLUE)Setting up Keycloak configuration (interactive)...$(NC)"
	@if [ -f scripts/setup-automation.sh ]; then \
		chmod +x scripts/setup-automation.sh && \
		scripts/setup-automation.sh -u $(KEYCLOAK_URL) -r $(REALM_NAME) -e $(ENVIRONMENT); \
	else \
		echo "$(RED)Setup automation script not found$(NC)"; \
		exit 1; \
	fi

setup-auto: ## Set up Keycloak realm and service accounts (automated, no prompts)
	@echo "$(BLUE)Setting up Keycloak configuration (automated)...$(NC)"
	@if [ -f scripts/setup-automation.sh ]; then \
		chmod +x scripts/setup-automation.sh && \
		scripts/setup-automation.sh -u $(KEYCLOAK_URL) -r $(REALM_NAME) -e $(ENVIRONMENT) --auto-approve; \
	else \
		echo "$(RED)Setup automation script not found$(NC)"; \
		exit 1; \
	fi

setup-legacy: ## Set up using legacy script (for compatibility)
	@echo "$(BLUE)Setting up Keycloak configuration (legacy)...$(NC)"
	@if [ -f scripts/setup-keycloak.sh ]; then \
		chmod +x scripts/setup-keycloak.sh && \
		scripts/setup-keycloak.sh -u $(KEYCLOAK_URL) -r $(REALM_NAME) -e $(ENVIRONMENT); \
	else \
		echo "$(RED)Legacy setup script not found$(NC)"; \
		exit 1; \
	fi

validate: ## Validate Keycloak configuration
	@echo "$(BLUE)Validating Keycloak configuration...$(NC)"
	@if [ -f scripts/validate-keycloak.sh ]; then \
		chmod +x scripts/validate-keycloak.sh && \
		scripts/validate-keycloak.sh -u $(KEYCLOAK_URL) -r $(REALM_NAME) -e $(ENVIRONMENT); \
	else \
		echo "$(RED)Validation script not found$(NC)"; \
		exit 1; \
	fi

start: ## Start Keycloak using Docker Compose
	@echo "$(BLUE)Starting Keycloak services...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) up -d
	@echo "$(GREEN)Keycloak services started$(NC)"
	@echo "Waiting for Keycloak to be ready..."
	@timeout 120 bash -c 'until curl -s -f $(KEYCLOAK_URL)/health/ready > /dev/null 2>&1; do sleep 5; done' || \
		(echo "$(RED)Keycloak failed to start within 2 minutes$(NC)" && exit 1)
	@echo "$(GREEN)Keycloak is ready at $(KEYCLOAK_URL)$(NC)"

stop: ## Stop Keycloak services
	@echo "$(BLUE)Stopping Keycloak services...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) down
	@echo "$(GREEN)Keycloak services stopped$(NC)"

restart: stop start ## Restart Keycloak services

logs: ## Show Keycloak logs
	@docker-compose -f $(COMPOSE_FILE) logs -f keycloak

logs-db: ## Show Keycloak database logs
	@docker-compose -f $(COMPOSE_FILE) logs -f keycloak-db

status: ## Show status of Keycloak services
	@echo "$(BLUE)Keycloak services status:$(NC)"
	@docker-compose -f $(COMPOSE_FILE) ps
	@echo ""
	@echo "$(BLUE)Health check:$(NC)"
	@curl -s $(KEYCLOAK_URL)/health/ready > /dev/null 2>&1 && \
		echo "$(GREEN)✓ Keycloak is ready$(NC)" || \
		echo "$(RED)✗ Keycloak is not ready$(NC)"

clean: ## Clean up Keycloak data and containers
	@echo "$(YELLOW)Warning: This will remove all Keycloak data!$(NC)"
	@read -p "Are you sure? (y/N): " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(BLUE)Cleaning up Keycloak...$(NC)"; \
		docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans; \
		docker volume rm $$(docker volume ls -q | grep keycloak) 2>/dev/null || true; \
		echo "$(GREEN)Cleanup completed$(NC)"; \
	else \
		echo "$(YELLOW)Cleanup cancelled$(NC)"; \
	fi

backup: ## Backup Keycloak database
	@echo "$(BLUE)Creating Keycloak database backup...$(NC)"
	@mkdir -p backups
	@docker exec eagle-keycloak-db pg_dump -U keycloak keycloak > backups/keycloak-backup-$$(date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)Backup created in backups/ directory$(NC)"

restore: ## Restore Keycloak database from backup
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -la backups/*.sql 2>/dev/null || (echo "$(RED)No backups found$(NC)" && exit 1)
	@read -p "Enter backup filename: " backup_file; \
	if [ -f "backups/$$backup_file" ]; then \
		echo "$(BLUE)Restoring from $$backup_file...$(NC)"; \
		docker exec -i eagle-keycloak-db psql -U keycloak keycloak < "backups/$$backup_file"; \
		echo "$(GREEN)Restore completed$(NC)"; \
	else \
		echo "$(RED)Backup file not found$(NC)"; \
		exit 1; \
	fi

test: ## Test service account token generation
	@echo "$(BLUE)Testing service account token generation...$(NC)"
	@echo "Testing ms-customer..."
	@curl -s -X POST $(KEYCLOAK_URL)/realms/$(REALM_NAME)/protocol/openid-connect/token \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-d "grant_type=client_credentials" \
		-d "client_id=ms-customer" \
		-d "client_secret=customer-secret" \
		-d "scope=microservice-communication" | \
		jq -r 'if .access_token then "$(GREEN)✓ ms-customer token generation successful$(NC)" else "$(RED)✗ ms-customer token generation failed$(NC)" end'
	@echo "Testing ms-alert..."
	@curl -s -X POST $(KEYCLOAK_URL)/realms/$(REALM_NAME)/protocol/openid-connect/token \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-d "grant_type=client_credentials" \
		-d "client_id=ms-alert" \
		-d "client_secret=alert-secret" \
		-d "scope=microservice-communication" | \
		jq -r 'if .access_token then "$(GREEN)✓ ms-alert token generation successful$(NC)" else "$(RED)✗ ms-alert token generation failed$(NC)" end'

dev: start setup validate ## Complete development setup (start + setup + validate)
	@echo "$(GREEN)Development environment is ready!$(NC)"
	@echo "$(BLUE)Keycloak Admin Console: $(KEYCLOAK_URL)/admin$(NC)"
	@echo "$(BLUE)Realm: $(REALM_NAME)$(NC)"

prod-setup: ## Setup for production environment
	@$(MAKE) setup ENVIRONMENT=prod KEYCLOAK_URL=https://keycloak.fusionx.pro REALM_NAME=eagle-prod

# Environment-specific targets
dev-env: ## Load development environment variables
	@echo "$(BLUE)Loading development environment...$(NC)"
	@if [ -f import/environments/dev.env ]; then \
		set -a && source import/environments/dev.env && set +a; \
		echo "$(GREEN)Development environment loaded$(NC)"; \
	else \
		echo "$(RED)Development environment file not found$(NC)"; \
	fi

prod-env: ## Load production environment variables
	@echo "$(BLUE)Loading production environment...$(NC)"
	@if [ -f import/environments/prod.env ]; then \
		set -a && source import/environments/prod.env && set +a; \
		echo "$(GREEN)Production environment loaded$(NC)"; \
	else \
		echo "$(RED)Production environment file not found$(NC)"; \
	fi

# Utility targets
check-deps: ## Check required dependencies
	@echo "$(BLUE)Checking dependencies...$(NC)"
	@command -v docker >/dev/null 2>&1 || (echo "$(RED)✗ Docker not found$(NC)" && exit 1)
	@echo "$(GREEN)✓ Docker found$(NC)"
	@command -v docker-compose >/dev/null 2>&1 || (echo "$(RED)✗ Docker Compose not found$(NC)" && exit 1)
	@echo "$(GREEN)✓ Docker Compose found$(NC)"
	@command -v curl >/dev/null 2>&1 || (echo "$(RED)✗ curl not found$(NC)" && exit 1)
	@echo "$(GREEN)✓ curl found$(NC)"
	@command -v jq >/dev/null 2>&1 || (echo "$(RED)✗ jq not found$(NC)" && exit 1)
	@echo "$(GREEN)✓ jq found$(NC)"
	@echo "$(GREEN)All dependencies are available$(NC)"

info: ## Show configuration information
	@echo "$(BLUE)Keycloak Configuration Information$(NC)"
	@echo "=================================="
	@echo "Keycloak URL:     $(KEYCLOAK_URL)"
	@echo "Realm Name:       $(REALM_NAME)"
	@echo "Environment:      $(ENVIRONMENT)"
	@echo "Compose File:     $(COMPOSE_FILE)"
	@echo ""
	@echo "$(BLUE)Important Endpoints:$(NC)"
	@echo "Admin Console:    $(KEYCLOAK_URL)/admin"
	@echo "Token Endpoint:   $(KEYCLOAK_URL)/realms/$(REALM_NAME)/protocol/openid-connect/token"
	@echo "JWKS Endpoint:    $(KEYCLOAK_URL)/realms/$(REALM_NAME)/protocol/openid-connect/certs"
	@echo "Health Endpoint:  $(KEYCLOAK_URL)/health/ready"
#
 New automation scripts
backup-config: ## Backup Keycloak configuration via Admin API
	@echo "$(BLUE)Creating Keycloak configuration backup...$(NC)"
	@mkdir -p backups
	@if [ -f scripts/keycloak-admin-api.sh ]; then \
		chmod +x scripts/keycloak-admin-api.sh && \
		KEYCLOAK_URL=$(KEYCLOAK_URL) REALM_NAME=$(REALM_NAME) ENVIRONMENT=$(ENVIRONMENT) \
		scripts/keycloak-admin-api.sh backup; \
	else \
		echo "$(RED)Admin API script not found$(NC)"; \
		exit 1; \
	fi

validate-config: ## Validate Keycloak configuration using enhanced validation
	@echo "$(BLUE)Validating Keycloak configuration (enhanced)...$(NC)"
	@if [ -f scripts/validate-keycloak.sh ]; then \
		chmod +x scripts/validate-keycloak.sh && \
		KEYCLOAK_URL=$(KEYCLOAK_URL) REALM_NAME=$(REALM_NAME) ENVIRONMENT=$(ENVIRONMENT) \
		scripts/validate-keycloak.sh; \
	else \
		echo "$(RED)Enhanced validation script not found$(NC)"; \
		exit 1; \
	fi

admin-api: ## Run Admin API operations (setup/validate/backup)
	@echo "$(BLUE)Available Admin API operations:$(NC)"
	@echo "  setup    - Setup complete realm configuration"
	@echo "  validate - Validate current configuration"  
	@echo "  backup   - Backup current configuration"
	@read -p "Enter operation (setup/validate/backup): " operation; \
	if [ -f scripts/keycloak-admin-api.sh ]; then \
		chmod +x scripts/keycloak-admin-api.sh && \
		KEYCLOAK_URL=$(KEYCLOAK_URL) REALM_NAME=$(REALM_NAME) ENVIRONMENT=$(ENVIRONMENT) \
		scripts/keycloak-admin-api.sh $$operation; \
	else \
		echo "$(RED)Admin API script not found$(NC)"; \
		exit 1; \
	fi

# Complete automation workflows
dev-auto: start setup-auto validate-config ## Complete automated development setup
	@echo "$(GREEN)Automated development environment is ready!$(NC)"
	@echo "$(BLUE)Keycloak Admin Console: $(KEYCLOAK_URL)/admin$(NC)"
	@echo "$(BLUE)Realm: $(REALM_NAME)$(NC)"

prod-auto: ## Complete automated production setup
	@$(MAKE) setup-auto ENVIRONMENT=prod KEYCLOAK_URL=https://keycloak.fusionx.pro REALM_NAME=eagle-prod
	@$(MAKE) validate-config ENVIRONMENT=prod KEYCLOAK_URL=https://keycloak.fusionx.pro REALM_NAME=eagle-prod

# Windows PowerShell helpers
ps-setup: ## Setup using PowerShell scripts (Windows)
	@echo "$(BLUE)Running PowerShell setup automation...$(NC)"
	@echo "Execute: .\scripts\setup-automation.ps1 -Environment $(ENVIRONMENT) -KeycloakUrl $(KEYCLOAK_URL) -RealmName $(REALM_NAME)"

ps-validate: ## Validate using PowerShell scripts (Windows)
	@echo "$(BLUE)Running PowerShell validation...$(NC)"
	@echo "Execute: .\scripts\validate-keycloak.ps1 -Environment $(ENVIRONMENT) -KeycloakUrl $(KEYCLOAK_URL) -RealmName $(REALM_NAME)"

ps-backup: ## Backup using PowerShell scripts (Windows)
	@echo "$(BLUE)Running PowerShell backup...$(NC)"
	@echo "Execute: .\scripts\keycloak-admin-api.ps1 -Environment $(ENVIRONMENT) -KeycloakUrl $(KEYCLOAK_URL) -RealmName $(REALM_NAME) -Action backup"