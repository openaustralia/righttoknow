#!/bin/sh

# Bootstrap a Right to Know development environment inside the app container.
#
# Idempotent: safe to re-run at any time. On first run it clones the
# openaustralia/alaveteli fork into /alaveteli (a Docker volume), wires this
# theme in with Alaveteli's switch-theme script, then migrates and seeds the
# databases and builds the search index. Subsequent runs update gems, re-link
# the theme and run any pending migrations, but leave the sample data alone
# unless --reset-data is passed.
#
# Runs as the Dev Container onCreateCommand, and via `make setup` for the
# plain Docker workflow. Mirrors the steps in alaveteli's docker/bootstrap and
# docker/setup scripts.

set -e

ALAVETELI_DIR=/alaveteli
THEME_DIR=/alaveteli-themes/righttoknow
ALAVETELI_REPO="${ALAVETELI_REPO:-https://github.com/openaustralia/alaveteli.git}"
ALAVETELI_BRANCH="${ALAVETELI_BRANCH:-staging}"

error_msg() { printf "\033[31m%s\033[0m\n" "$*"; }
notice_msg() { printf "\033[33m%s\033[0m " "$*"; }
success_msg() { printf "\033[32m%s\033[0m\n" "$*"; }

notice_msg "Waiting for the database..."
wait-for-it db:5432 --strict --timeout=120 -- true
success_msg 'done'

if [ ! -d "$ALAVETELI_DIR/.git" ]; then
  notice_msg "Cloning $ALAVETELI_REPO ($ALAVETELI_BRANCH)..."
  git clone --branch "$ALAVETELI_BRANCH" "$ALAVETELI_REPO" "$ALAVETELI_DIR"
  success_msg 'done'
fi

cd "$ALAVETELI_DIR"

notice_msg "Syncing git submodules..."
git submodule update --init
success_msg 'done'

notice_msg "Copying example config files..."
[ ! -f config/database.yml ] && cp config/database.yml-example config/database.yml
[ ! -f config/sidekiq.yml ] && cp config/sidekiq.yml-example config/sidekiq.yml
[ ! -f config/storage.yml ] && cp config/storage.yml-example config/storage.yml
[ ! -f config/general-righttoknow.yml ] &&
  cp "$THEME_DIR/config/general-righttoknow.yml.example" config/general-righttoknow.yml
success_msg 'done'

notice_msg 'Installing Ruby gems...'
bundle check >/dev/null || bundle install
success_msg 'done'

notice_msg 'Switching to the righttoknow theme...'
# Same symlinks as alaveteli's script/switch-theme.rb, done directly because
# that script skips checkouts whose .git is a gitfile (e.g. git worktrees).
ln -sfn general-righttoknow.yml config/general.yml
ln -sfn "$THEME_DIR/public" public/alavetelitheme
mkdir -p lib/themes
ln -sfn "$THEME_DIR" lib/themes/righttoknow
bin/rails assets:clean >/dev/null
success_msg 'done'

# Sample data is loaded once, on a database that has never been seeded. Pass
# --reset-data to force a reload.
set +e
bin/rails runner 'User.find(1)' >/dev/null 2>&1
RESET_DATA_FLAG=$?
set -e
for arg in "$@"; do
  case $arg in
    --reset-data) RESET_DATA_FLAG=1;;
    *);;
  esac
done

# Migrations run every time, not just on first setup: /alaveteli is a
# persistent volume, so a re-run after the checkout moves to a revision with
# new migrations is exactly when the schemas would otherwise go stale. Both
# db:migrate and db:seed are idempotent.
notice_msg 'Migrating development and test databases...'
bin/rails db:migrate db:seed >/dev/null
bin/rails db:migrate RAILS_ENV=test >/dev/null
success_msg 'done'

if [ $RESET_DATA_FLAG -eq 0 ]; then
  success_msg 'Sample data already loaded; skipping'
  success_msg 'Setup finished'
  exit 0
fi

notice_msg 'Loading sample data...'
bundle exec script/load-sample-data >/dev/null
success_msg 'done'

notice_msg 'Removing external requests...'
bin/rails runner 'InfoRequest.external.destroy_all'
success_msg 'done'

notice_msg 'Rebuilding Xapian index...'
bundle exec script/destroy-and-rebuild-xapian-index >/dev/null
success_msg 'done'

success_msg 'Setup finished'
