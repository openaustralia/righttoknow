# Docker-based development workflow for the Right to Know theme.
#
# The stack is defined in .devcontainer/compose.yaml and shared with the Dev Container, so you can develop with plain
# Docker and any editor. See "Docker development environment" in AGENTS.md.
# --wait returns once every service passes its healthcheck, so the next command can use them straight away.

COMPOSE := docker compose
# Runs a command in the app container, or in a fresh one if it has stopped, with any options for docker compose
in_app = if [ -n "$$($(COMPOSE) ps -q --status running app)" ]; then $(COMPOSE) exec $(2) app $(1); else $(COMPOSE) run --rm $(2) app $(1); fi
# The seed script's settings that are set, passed into the container (an empty one would override its default)
SEED_ENV = $(foreach v,SEED_CSV_URL SEED_CSV_PATH SEED_BODIES_PER_TAG,$(if $($(v)),-e $(v)))

.PHONY: help setup up services-up down clean clobber status logs shell console test lint seed reset

help: ## Show this help (the default target)
	@grep -hE '^[a-zA-Z0-9_.-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

# The theme only runs inside Alaveteli, so on the host this is for deploying and linting; run the site with `make up`.
# mise is preferred, rbenv works too; both read .ruby-version (mise via mise.toml).
setup: ## Install Ruby (with mise or rbenv) and the theme's gems, for deploying and linting on the host
	@if command -v mise >/dev/null; then mise trust && mise install && mise exec -- bundle install; \
	elif command -v rbenv >/dev/null; then rbenv install --skip-existing && rbenv exec bundle install; \
	else echo "Install mise (https://mise.jdx.dev) or rbenv first" >&2; exit 1; fi

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
	@$(call in_app,bash)

# See "Tests and linting" in AGENTS.md. The specs run from the host app, so ARGS paths are relative to this repo.
test: ## Run this theme's specs, after preparing the test database (ARGS=spec/x_spec.rb:42 to narrow)
	@$(call in_app,bash -c 'cd /alaveteli && RAILS_ENV=test bin/rails db:prepare && \
	  bundle exec rspec $(addprefix lib/themes/righttoknow/,$(or $(ARGS),spec))')
# CI installs this RuboCop version on its own rather than the one in Gemfile.lock, so this does too
lint: ## Run RuboCop as CI does (ARGS=<paths> to narrow)
	@$(call in_app,bash -c 'cd /alaveteli-themes/righttoknow && \
	  { gem list -i rubocop -v 1.80.2 >/dev/null || gem install --no-document rubocop -v 1.80.2; } && \
	  rubocop _1.80.2_ $(ARGS)')
console: ## Open a Rails console in the app container
	@$(call in_app,bash -c 'cd /alaveteli && bin/rails console')
seed: ## Load realistic AU authorities and requests (SEED_BODIES_PER_TAG=5 and the like, see "Seeding test data")
	@$(call in_app,bash -c 'cd /alaveteli && SEED_REBUILD_INDEX=1 bundle exec rails runner \
	  /alaveteli-themes/righttoknow/script/seed_test_data.rb',$(SEED_ENV))
reset: clobber ## Remove everything, then start again from scratch
	$(MAKE) up
