# frozen_string_literal: true

# Warn about Sidekiq queues that have pending jobs but no worker to drain them.
#
# Alaveteli enqueues to queue names hardcoded in the application - for example
# FoiAttachmentMaskJob uses `low`, introduced in 0.45.x. If sidekiq.yml does not
# list a queue, jobs pushed to it accumulate in Redis forever: Sidekiq never
# picks them up, nothing raises, and no job is recorded as failed. The symptom is
# silent, so a feature simply stops working with nothing in the logs. This makes
# that state noisy instead.
#
# ---------------------------------------------------------------------------
# Run from the Alaveteli app root:
#
#   bundle exec rails runner lib/themes/righttoknow/script/check_orphaned_queues.rb
#
# The infrastructure repo installs an hourly cron entry that does exactly this.
# Anything printed to stdout becomes cron mail, which reaches
# web-administrators@openaustralia.org and the #righttoknow-log Slack channel, so
# this MUST stay silent when everything is healthy.
# ---------------------------------------------------------------------------

require 'sidekiq/api'
require 'yaml'

# Sidekiq's config lives in the shared path and is symlinked into the release as
# config/sidekiq.yml by the deploy.
config_path = Rails.root.join('config/sidekiq.yml')

unless File.exist?(config_path)
  warn "check_orphaned_queues: #{config_path} not found"
  exit 1
end

config = YAML.load_file(config_path) || {}

# Sidekiq's config file spells the key ":queues", which Psych parses as the
# Symbol :queues rather than a string. Accept the plain-string spellings too, so
# this keeps working if the file is ever normalised.
configured = Array(
  config[:queues] || config[':queues'] || config['queues']
).map(&:to_s)

if configured.empty?
  warn "check_orphaned_queues: no :queues listed in #{config_path}"
  exit 1
end

pending = Sidekiq::Queue.all.select { |queue| queue.size.positive? }
orphaned = pending.reject { |queue| configured.include?(queue.name) }

exit 0 if orphaned.empty?

summary = orphaned.map { |queue| "#{queue.name} (#{queue.size} jobs)" }.join(', ')

puts <<~MESSAGE
  WARNING: Sidekiq queues have pending jobs but are not listed in sidekiq.yml, so
  no worker will ever process them: #{summary}

  Configured queues: #{configured.join(', ')}

  Fix by adding the queue to :queues (and usually :limits) in
  roles/internal/righttoknow/templates/sidekiq.yml.j2 in the infrastructure
  repository, then re-applying the righttoknow role.
MESSAGE
