# Docker-based development workflow for the Right to Know theme.
#
# The stack is defined in .devcontainer/compose.yaml and shared with the Dev Container, so you can develop with plain
# Docker and any editor. See "Docker development environment" in AGENTS.md.
# --wait returns once every service passes its healthcheck, so the next command can use them straight away.

COMPOSE := docker compose
IN_APP  := $(COMPOSE) exec app sh -c

.PHONY: help up services-up down clean clobber status logs shell console test seed reset

help: ## Show this help (the default target)
	@grep -hE '^[a-zA-Z0-9_.-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

up: ## Start everything, including the site at http://localhost:3000 (the first run clones Alaveteli and takes a while)
	$(COMPOSE) up --build --wait -d
services-up: ## Start PostgreSQL, Redis and MailHog only
	$(COMPOSE) up --build --wait -d db redis mailhog
down: ## Stop and remove the containers, keeping the data
	$(COMPOSE) down --remove-orphans
# Everything this checkout built, so the next `make up` rebuilds from scratch. The data is kept.
# VS Code's dev container builds its own images on top of compose's. Only this project's containers say which
# they are, so they're noted before `down` removes them.
clean: ## Remove containers, built images (VS Code's too), gems and the Alaveteli clone, keeping the data
	p=$$($(COMPOSE) config | sed -n 's/^name: //p'); \
	vsc=$$(docker ps -a --filter "label=com.docker.compose.project=$$p" --format '{{.Image}}' | grep '^vsc-' | sort -u); \
	$(COMPOSE) down --remove-orphans --rmi local && \
	docker volume rm --force "$${p}_alaveteli" "$${p}_bundle" && \
	{ [ -z "$$vsc" ] || docker rmi --force $$vsc; }
# Reaches past this checkout, for after switching branches or changing dependencies. Other projects lose only
# download and build time, as volumes (where their databases live) are never pruned.
clobber: clean ## Also remove the data, then all stopped containers, unused images and build cache machine-wide
	$(COMPOSE) down --volumes
	@echo "Pruning stopped containers, unused images and build cache from ALL projects (volumes are kept)"
	docker system prune --all --force
status: ## Show each container's health and the host ports it's published on
	@$(COMPOSE) ps -a --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
logs: ## Follow the logs of every container (or SERVICE=app for one)
	$(COMPOSE) logs -f $(SERVICE)
shell: ## Open a shell in the app container, or in a fresh one if it has stopped (e.g. after a failed start)
	@if [ -n "$$(docker compose ps -q --status running app)" ]; then docker compose exec app bash; else docker compose run --rm app bash; fi

console: ## Open a Rails console
	$(IN_APP) 'cd /alaveteli && bin/rails console'
test: ## Run this theme's specs
	$(IN_APP) 'cd /alaveteli && bundle exec rspec lib/themes/righttoknow/spec'
seed: ## Load realistic AU authorities and requests (see script/seed_test_data.rb)
	$(IN_APP) 'cd /alaveteli && SEED_REBUILD_INDEX=1 bundle exec rails runner \
	  /alaveteli-themes/righttoknow/script/seed_test_data.rb'
reset: clobber ## Remove everything, then start again from scratch
	$(MAKE) up
