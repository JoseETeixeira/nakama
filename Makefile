# Makefile for Nakama MMORPG Development

.PHONY: help build-modules up up-build down restart logs clean

help: ## Show this help message
	@echo "Nakama MMORPG Development Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

build-modules: ## Compile TypeScript modules to JavaScript
	@echo "🔨 Building TypeScript modules..."
	@npm run build

watch-modules: ## Watch and auto-compile TypeScript modules
	@echo "👀 Watching TypeScript modules..."
	@npm run watch

up: build-modules ## Build modules and start Docker Compose stack
	@echo "🚀 Starting Nakama stack..."
	@docker compose up

up-build: build-modules ## Build modules and start with Docker image rebuild
	@echo "🚀 Building and starting Nakama stack..."
	@docker compose up --build

down: ## Stop Docker Compose stack
	@docker compose down

restart: build-modules ## Rebuild modules and restart Nakama container
	@echo "🔄 Restarting Nakama..."
	@docker compose restart nakama

logs: ## Show Nakama logs
	@docker compose logs -f nakama

clean: ## Clean compiled JavaScript files
	@echo "🧹 Cleaning compiled modules..."
	@find data/modules -name "*.js" -type f -delete
	@echo "✓ Cleaned"

dev: ## Start development mode with watch
	@echo "🔥 Starting development mode..."
	@npm run watch &
	@docker compose up
