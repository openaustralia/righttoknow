# Docker-based development workflow for the Right to Know theme.
#
# Uses the same compose stack as the Dev Container (.devcontainer/), so you
# can develop with plain Docker and any editor — no VS Code required.
# Run `make setup` once, then `make server` and open http://localhost:3000.

COMPOSE := docker compose -f .devcontainer/docker-compose.yml
APP     := $(COMPOSE) exec app
IN_APP  := $(APP) sh -c

.PHONY: help setup server console test seed shell logs stop down reset

help: ## Show this help
	@grep -E '^[a-z][a-zA-Z_-]*:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Build images, start services and bootstrap Alaveteli + this theme
	$(COMPOSE) build
	$(COMPOSE) up -d
	$(APP) /alaveteli-themes/righttoknow/.devcontainer/setup.sh

server: ## Run the Rails server (then open http://localhost:3000)
	$(COMPOSE) up -d
	$(IN_APP) 'cd /alaveteli && rm -f tmp/pids/server.pid && bin/rails server -b 0.0.0.0'

console: ## Open a Rails console
	$(IN_APP) 'cd /alaveteli && bin/rails console'

test: ## Run this theme's specs
	$(IN_APP) 'cd /alaveteli && bundle exec rspec lib/themes/righttoknow/spec'

seed: ## Load realistic AU authorities and requests (see script/seed_test_data.rb)
	$(IN_APP) 'cd /alaveteli && SEED_REBUILD_INDEX=1 bundle exec rails runner \
	  /alaveteli-themes/righttoknow/script/seed_test_data.rb'

shell: ## Open a shell in the app container
	$(APP) bash

logs: ## Tail service logs
	$(COMPOSE) logs -f

stop: ## Stop services (keeps data)
	$(COMPOSE) stop

down: ## Stop and remove containers (keeps data volumes)
	$(COMPOSE) down

reset: ## Destroy everything (containers AND data volumes) and set up again
	$(COMPOSE) down --volumes
	$(MAKE) setup
