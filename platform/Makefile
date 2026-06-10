# =============================================================================
# Frappe Platform — Makefile
#
# Wraps docker compose and org-bench commands so developers don't need to
# remember long compose flags or file paths.
#
# Usage:
#   make help              Show all available targets
#   make dev-setup         First-time environment initialisation
#   make dev-start         Start the local dev stack
#   make dev-stop          Stop the local stack (data preserved)
#   make dev-destroy       Stop and delete all volumes (full reset)
#   make dev-logs          Follow all service logs
#   make dev-shell         Open a bash shell in the frappe-web container
#   make dev-new-app name=myapp   Scaffold a new Frappe app
#   make build tag=v1.0.0  Build the production image
#   make deploy-nomad tag=v1.0.0 env=prod   Deploy to Nomad
#   make deploy-dokploy tag=v1.0.0 env=prod Deploy via Dokploy
# =============================================================================

# Ensure bash is used for all recipe shells (needed for read -p, [[ ]], etc.)
SHELL := /bin/bash

# Load .env if it exists so make targets can reference env vars directly
-include .env
export

COMPOSE      := docker compose -f docker-compose.dev.yml --env-file .env
PLATFORM_DIR := $(shell pwd)
ENV_FILE     := $(PLATFORM_DIR)/.env
ORG_BENCH    := ORG_BENCH_PLATFORM_DIR=$(PLATFORM_DIR) org-bench

# Detect OS for platform-specific helpers
UNAME := $(shell uname -s)

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "Frappe Platform — available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------
.PHONY: check-env
check-env:
	@test -f $(ENV_FILE) || (echo "ERROR: platform/.env not found. Run 'make dev-setup' first." && exit 1)

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------
.PHONY: dev-setup
dev-setup: ## Initialise .env, pull base images, check /etc/hosts
	$(ORG_BENCH) dev setup
	@SITE=$${FRAPPE_SITE_NAME:-dev.localhost}; \
	if ! grep -qE "^\s*127\.0\.0\.1\s+$$SITE" /etc/hosts 2>/dev/null; then \
		echo ""; \
		echo "  WARNING: '$$SITE' not found in /etc/hosts."; \
		echo "  Add this line to /etc/hosts to access the site by hostname:"; \
		echo "    127.0.0.1  $$SITE"; \
		if [ "$(UNAME)" = "Darwin" ]; then \
			echo "  On macOS: sudo sh -c 'echo \"127.0.0.1 $$SITE\" >> /etc/hosts'"; \
		else \
			echo "  On Linux/WSL2: echo '127.0.0.1 $$SITE' | sudo tee -a /etc/hosts"; \
		fi; \
		echo ""; \
	fi

.PHONY: dev-start
dev-start: check-env ## Build images (if needed) and start the full local stack
	$(ORG_BENCH) dev start

.PHONY: dev-stop
dev-stop: check-env ## Stop the stack, preserve data volumes
	$(COMPOSE) down

.PHONY: dev-destroy
dev-destroy: check-env ## Full reset: stop stack, delete volumes AND bench directory
	@echo "WARNING: This will delete all site data, MariaDB volumes, AND development/frappe-bench."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	$(COMPOSE) down -v
	rm -rf $(PLATFORM_DIR)/../development/frappe-bench
	@echo "Bench directory removed. Next 'make dev-start' will rebuild from scratch."

.PHONY: dev-restart
dev-restart: check-env ## Restart all services (rolling restart, no rebuild)
	$(COMPOSE) restart

.PHONY: dev-rebuild
dev-rebuild: check-env ## Rebuild images from scratch and restart
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

.PHONY: dev-logs
dev-logs: check-env ## Follow logs from all services (Ctrl-C to stop)
	$(COMPOSE) logs -f

.PHONY: dev-logs-web
dev-logs-web: check-env ## Follow logs from frappe-web only
	$(COMPOSE) logs -f frappe-web

.PHONY: dev-logs-bootstrap
dev-logs-bootstrap: check-env ## Follow bootstrap init logs
	$(COMPOSE) logs -f bootstrap

.PHONY: dev-shell
dev-shell: check-env ## Open bash shell in the frappe-web container
	$(COMPOSE) exec frappe-web bash

.PHONY: dev-console
dev-console: check-env ## Open Frappe bench Python console
	$(COMPOSE) exec frappe-web bash -c "bench --site $${FRAPPE_SITE_NAME:-dev.localhost} console"

.PHONY: dev-new-app
dev-new-app: check-env ## Scaffold a new Frappe app — usage: make dev-new-app name=myapp
ifndef name
	$(error Usage: make dev-new-app name=<app_name>)
endif
	$(ORG_BENCH) dev new-app $(name)

.PHONY: dev-migrate
dev-migrate: check-env ## Run bench migrate on the dev site
	$(COMPOSE) exec frappe-web bash -c "bench --site $${FRAPPE_SITE_NAME:-dev.localhost} migrate"

.PHONY: dev-clear-cache
dev-clear-cache: check-env ## Clear Frappe cache on the dev site
	$(COMPOSE) exec frappe-web bash -c "bench --site $${FRAPPE_SITE_NAME:-dev.localhost} clear-cache"

.PHONY: dev-backup
dev-backup: check-env ## Backup the dev site
	$(COMPOSE) exec frappe-web bash -c "bench --site $${FRAPPE_SITE_NAME:-dev.localhost} backup --with-files"

.PHONY: dev-get-app
dev-get-app: check-env ## Get and install an app — usage: make dev-get-app url=https://github.com/org/app branch=main
ifndef url
	$(error Usage: make dev-get-app url=<repo-url> [branch=<branch>])
endif
	$(COMPOSE) exec frappe-web bash -c "\
		cd /workspace/development/frappe-bench && \
		bench get-app --branch $${branch:-main} $(url) && \
		bench --site $${FRAPPE_SITE_NAME:-dev.localhost} install-app $$(basename $(url) .git)"

.PHONY: dev-mariadb
dev-mariadb: check-env ## Open MariaDB console for the dev site
	$(COMPOSE) exec frappe-web bash -c "cd /workspace/development/frappe-bench && bench --site $${FRAPPE_SITE_NAME:-dev.localhost} mariadb"

.PHONY: dev-export-fixtures
dev-export-fixtures: check-env ## Export fixtures for all apps (or: make dev-export-fixtures app=nusakura_app)
ifdef app
	$(COMPOSE) exec frappe-web bash -c "cd /workspace/development/frappe-bench && bench --site $${FRAPPE_SITE_NAME:-dev.localhost} export-fixtures --app $(app)"
else
	$(COMPOSE) exec frappe-web bash -c "cd /workspace/development/frappe-bench && bench --site $${FRAPPE_SITE_NAME:-dev.localhost} export-fixtures"
endif

.PHONY: dev-ps
dev-ps: check-env ## Show running service status
	$(COMPOSE) ps

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
.PHONY: build
build: check-env ## Build production image — usage: make build tag=v1.0.0
ifndef tag
	$(error Usage: make build tag=<version>)
endif
	$(ORG_BENCH) build --tag $(tag)

.PHONY: build-push
build-push: check-env ## Build and push production image — usage: make build-push tag=v1.0.0
ifndef tag
	$(error Usage: make build-push tag=<version>)
endif
	$(ORG_BENCH) build --tag $(tag) --push

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
.PHONY: deploy-nomad
deploy-nomad: check-env ## Deploy to Nomad — usage: make deploy-nomad tag=v1.0.0 env=prod
ifndef tag
	$(error Usage: make deploy-nomad tag=<version> env=<prod|staging>)
endif
ifndef env
	$(error Usage: make deploy-nomad tag=<version> env=<prod|staging>)
endif
	$(ORG_BENCH) deploy --env $(env) --tag $(tag) --mode ship

.PHONY: deploy-dokploy
deploy-dokploy: check-env ## Deploy via Dokploy — usage: make deploy-dokploy tag=v1.0.0 env=prod
ifndef tag
	$(error Usage: make deploy-dokploy tag=<version> env=<prod|staging>)
endif
ifndef env
	$(error Usage: make deploy-dokploy tag=<version> env=<prod|staging>)
endif
	$(ORG_BENCH) deploy --env $(env) --tag $(tag) --mode dokploy

.PHONY: deploy-dry-run
deploy-dry-run: check-env ## Nomad job plan (dry run) — usage: make deploy-dry-run tag=v1.0.0 env=prod
ifndef tag
	$(error Usage: make deploy-dry-run tag=<version> env=<prod|staging>)
endif
ifndef env
	$(error Usage: make deploy-dry-run tag=<version> env=<prod|staging>)
endif
	$(ORG_BENCH) deploy --env $(env) --tag $(tag) --mode ship --dry-run
